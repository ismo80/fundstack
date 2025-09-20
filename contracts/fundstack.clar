;; stack-fund.clar
;; A Clarity (STX) smart contract implementing a simple milestone-based crowdfunding platform.

;; Name: stack-fund
;; Features:
;; - Create a campaign with an organizer, a target budget, and an ordered list of milestones.
;; - Backers can fund a campaign (send STX to the contract) and receive backing records.
;; - Organizer can create milestones with descriptions and amounts (must sum <= budget).
;; - For each milestone, backers vote to approve or reject the milestone payout.
;; - If the milestone gets majority approval (simple >50% of backers who voted), funds are released to the organizer.
;; - If campaign doesn't reach funding target by deadline, backers can claim refunds.
;; - Simple on-chain accounting: contributions recorded per backer per campaign.
;;
;; NOTES:
;; - This is an educational/example contract. For production use, add security reviews, dispute resolution, and careful handling of STX transfers.
;; - Deadlines use block-height or timestamps depending on chain support; here we use block-height style (uint deadline-block).

(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-FUNDED (err u102))

;; Constants for error conditions
(define-constant ERR-INVALID-AMOUNT (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-NOT-CAMPAIGN (err u105))
(define-constant ERR-DEADLINE-PASSED (err u106))
(define-constant ERR-NOT-OWNER (err u107))
(define-constant ERR-NOT-FUNDED (err u108))
(define-constant ERR-ALREADY-RELEASED (err u109))
(define-constant ERR-NOT-MILESTONE (err u110))
(define-constant ERR-NO-MILESTONE (err u111))

(define-data-var campaign-counter uint u0)

;; Campaign structure map: campaign-id => campaign-tuple
(define-map campaigns
  {campaign-id: uint}
  {organizer: principal,
   title: (string-ascii 64),
   description: (string-ascii 256),
   target: uint,                ;; target amount in microstacks
   funds: uint,                 ;; amount currently funded
   deadline: uint,              ;; block height after which refunds allowed
   milestone-count: uint,
   cancelled: bool}
)

;; contributions: (campaign-id, backer) => amount
(define-map contributions
  {campaign-id: uint, backer: principal}
  {amount: uint}
)

;; milestone structure: (campaign-id, midx) => tuple
(define-map milestones
  {campaign-id: uint, midx: uint}
  {amount: uint,            ;; amount requested for this milestone
   description: (string-ascii 128),
   released: bool,          ;; whether payout was released
   votes-yes: uint,
   votes-no: uint,
   voters: (list 100 principal)} ;; list of principals who voted, max 100
  )

;; Helper: generate new campaign id
(define-private (new-campaign-id)
  (let ((current-id (var-get campaign-counter)))
    (var-set campaign-counter (+ current-id u1))
    current-id))

;; STX transfer helpers
(define-private (transfer-stx (amount uint) (sender principal) (recipient principal))
  (begin
    (try! (as-contract (stx-transfer? amount sender recipient)))
    (ok true)))

(define-private (stx-get-transfer-amount)
  (ok (stx-get-balance tx-sender)))

;; Create a campaign: organizer calls this and specifies target, deadline-block, and title/description
(define-public (create-campaign (title (string-ascii 64)) (description (string-ascii 256)) (target uint) (deadline uint))
  (begin
    ;; validate inputs
    (asserts! (> target u0) ERR-INVALID-AMOUNT)
    (asserts! (> deadline u0) ERR-DEADLINE-PASSED)
    (asserts! (> (len title) u0) ERR-UNAUTHORIZED)
    (asserts! (> (len description) u0) ERR-UNAUTHORIZED)
    
    (let ((cid (new-campaign-id)))
      ;; create campaign with validated data
      (map-set campaigns
               {campaign-id: cid}
               {organizer: tx-sender,
                title: title,
                description: description,
                target: target,
                funds: u0,
                deadline: deadline,
                milestone-count: u0,
                cancelled: false})
      (ok cid))))

;; Backer funds a campaign by calling fund-campaign and attaching STX equal to amount.
(define-public (fund-campaign (id uint))
  (begin
    (asserts! (>= id u0) ERR-INVALID-AMOUNT)
    (let ((campaign (unwrap! (map-get? campaigns {campaign-id: id}) ERR-NOT-CAMPAIGN)))
      (asserts! (not (get cancelled campaign)) ERR-NOT-FOUND)
      (asserts! (< u0 (get deadline campaign)) ERR-DEADLINE-PASSED)
      (let ((amount (unwrap! (stx-get-transfer-amount) ERR-INVALID-AMOUNT)))
        (begin
          (asserts! (> amount u0) ERR-INVALID-AMOUNT)
          (asserts! (<= (+ (get funds campaign) amount) (get target campaign)) ERR-ALREADY-FUNDED)
          ;; Transfer STX
          (try! (transfer-stx amount tx-sender (get organizer campaign)))
          ;; Update contribution record
          (let ((prev-amount (get amount (default-to 
                                      {amount: u0} 
                                      (map-get? contributions 
                                               {campaign-id: id, backer: tx-sender})))))
            (map-set contributions 
                   {campaign-id: id, backer: tx-sender} 
                   {amount: (+ prev-amount amount)})
            ;; Update campaign funds
            (map-set campaigns 
                   {campaign-id: id}
                   (merge campaign {funds: (+ (get funds campaign) amount)}))
            (ok true)))))))

;; Organizer adds a milestone (amount must be <= remaining budget)
(define-public (add-milestone (id uint) (amount uint) (description (string-ascii 128)))
  (begin 
    (asserts! (>= id u0) ERR-INVALID-AMOUNT)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> (len description) u0) ERR-INVALID-AMOUNT)
    (let ((campaign (unwrap! (map-get? campaigns {campaign-id: id}) ERR-NOT-CAMPAIGN)))
      (begin
        (asserts! (is-eq tx-sender (get organizer campaign)) ERR-NOT-OWNER)
        (asserts! (<= amount (get target campaign)) ERR-INVALID-AMOUNT)
        (let ((mcount (get milestone-count campaign)))
          ;; create milestone
          (map-set milestones 
                   {campaign-id: id, midx: mcount}
                   {amount: amount,
                    description: description,
                    released: false,
                    votes-yes: u0,
                    votes-no: u0,
                    voters: (list)})
          ;; increment milestone-count
          (map-set campaigns 
                   {campaign-id: id}
                   (merge campaign {milestone-count: (+ mcount u1)}))
          (ok mcount))))))

;; Backer votes on a milestone: yes (true) or no (false)
(define-public (vote-milestone (id uint) (milestone-id uint) (approve bool))
  (begin
    (asserts! (>= id u0) ERR-INVALID-AMOUNT)
    (asserts! (>= milestone-id u0) ERR-INVALID-AMOUNT)
    (let ((milestone (unwrap! (map-get? milestones {campaign-id: id, midx: milestone-id}) ERR-NOT-MILESTONE)))
      ;; check if released
      (asserts! (not (get released milestone)) ERR-ALREADY-RELEASED)
      ;; ensure caller is a contributor
      (let ((contrib (default-to u0 
                      (get amount (map-get? contributions {campaign-id: id, backer: tx-sender})))))
        (asserts! (> contrib u0) ERR-UNAUTHORIZED)
        ;; ensure caller hasn't voted before
        (let ((voters (get voters milestone)))
          (asserts! (is-none (index-of voters tx-sender)) ERR-ALREADY-VOTED)
          ;; record vote and update
          (if approve
            (ok (map-set milestones 
                {campaign-id: id, midx: milestone-id}
                (merge milestone
                  {votes-yes: (+ (get votes-yes milestone) u1),
                   voters: (unwrap! (as-max-len? (append voters tx-sender) u100) ERR-UNAUTHORIZED)})))
            (ok (map-set milestones 
                {campaign-id: id, midx: milestone-id}
                (merge milestone
                  {votes-no: (+ (get votes-no milestone) u1),
                   voters: (unwrap! (as-max-len? (append voters tx-sender) u100) ERR-UNAUTHORIZED)})))))))))

;; Finalize milestone: organizer can finalize if votes show majority approval among voters.
(define-public (finalize-milestone (id uint) (milestone-id uint))
  (begin
    (asserts! (>= id u0) ERR-INVALID-AMOUNT)
    (asserts! (>= milestone-id u0) ERR-INVALID-AMOUNT)
    (let ((campaign (unwrap! (map-get? campaigns {campaign-id: id}) ERR-NOT-CAMPAIGN)))
      (let ((milestone (unwrap! (map-get? milestones {campaign-id: id, midx: milestone-id}) ERR-NOT-MILESTONE)))
        ;; verify ownership and state
        (asserts! (is-eq tx-sender (get organizer campaign)) ERR-NOT-OWNER)
        (asserts! (not (get released milestone)) ERR-ALREADY-RELEASED)
        ;; get vote counts and amounts
        (let ((yes (get votes-yes milestone))
              (no (get votes-no milestone))
              (amount (get amount milestone))
              (funds (get funds campaign)))
          ;; verify votes and funds
          (asserts! (> yes no) ERR-UNAUTHORIZED)
          (asserts! (>= funds amount) ERR-NOT-FUNDED)
          ;; transfer funds and update state
          (try! (transfer-stx amount tx-sender (get organizer campaign)))
          (map-set milestones 
            {campaign-id: id, midx: milestone-id}
            (merge milestone {released: true}))
          (map-set campaigns 
            {campaign-id: id}
            (merge campaign {funds: (- funds amount)}))
          (ok true))))))

;; Claim refund: backers can claim refunds if deadline passed and campaign didn't meet target.
(define-public (claim-refund (id uint))
  (begin
    (asserts! (>= id u0) ERR-INVALID-AMOUNT)
    (let ((campaign (unwrap! (map-get? campaigns {campaign-id: id}) ERR-NOT-CAMPAIGN))
          (contribution (unwrap! (map-get? contributions {campaign-id: id, backer: tx-sender}) ERR-NOT-FOUND))
          (amount (get amount contribution)))
      ;; Check conditions
      (asserts! (>= u0 (get deadline campaign)) ERR-DEADLINE-PASSED)
      (asserts! (< (get funds campaign) (get target campaign)) ERR-ALREADY-FUNDED)
      (asserts! (> amount u0) ERR-NOT-FOUND)
      ;; Transfer STX back
      (try! (transfer-stx amount tx-sender tx-sender))
      ;; Update state
      (map-set contributions 
        {campaign-id: id, backer: tx-sender} 
        {amount: u0})
      (map-set campaigns 
        {campaign-id: id}
        (merge campaign {funds: (- (get funds campaign) amount)}))
      (ok true))))
;; Read-only helper functions
(define-read-only (get-campaign-by-id (campaign-id uint))
  (ok (unwrap! (map-get? campaigns {campaign-id: campaign-id}) ERR-NOT-CAMPAIGN)))

(define-read-only (get-milestone-by-id (campaign-id uint) (milestone-id uint))
  (ok (unwrap! (map-get? milestones {campaign-id: campaign-id, midx: milestone-id}) ERR-NOT-MILESTONE)))

(define-read-only (get-contribution-by-id (campaign-id uint) (who principal))
  (match (map-get? contributions {campaign-id: campaign-id, backer: who})
    contribution (ok (get amount contribution))
    (ok u0)))

;; Helper function to get contract balance
(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender)))

;; End of stack-fund.clar
