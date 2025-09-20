# FundStack - Milestone-Based Crowdfunding Smart Contract

A Clarity smart contract for the Stacks blockchain that implements a milestone-based crowdfunding platform.

## Features

- **Campaign Creation**: Organizers can create campaigns with:
  - Target funding goal
  - Campaign deadline
  - Title and description
  - Multiple milestones

- **Milestone Management**:
  - Organizers can add milestones with specific funding amounts
  - Backers can vote on milestone completion
  - Funds are released only after majority approval

- **Funding System**:
  - Backers can fund campaigns using STX
  - Automatic tracking of contributions
  - Refund system if campaign fails to meet target

- **Security Features**:
  - Deadline enforcement using block height
  - Owner verification for sensitive operations
  - Vote tracking to prevent double voting
  - Maximum voter list size (100 voters per milestone)

## Functions

### Public Functions

- `create-campaign`: Create a new crowdfunding campaign
- `fund-campaign`: Back a campaign with STX
- `add-milestone`: Add a milestone to an existing campaign
- `vote-milestone`: Vote on milestone completion
- `finalize-milestone`: Release funds after successful vote
- `claim-refund`: Get refund if campaign fails

### Read-Only Functions

- `get-campaign-by-id`: Retrieve campaign details
- `get-milestone-by-id`: Get milestone information
- `get-contribution-by-id`: Check contribution amount
- `get-contract-balance`: View contract's STX balance

## Error Codes

```clarity
ERR-UNAUTHORIZED (u100)
ERR-NOT-FOUND (u101)
ERR-ALREADY-FUNDED (u102)
ERR-INVALID-AMOUNT (u103)
ERR-ALREADY-VOTED (u104)
ERR-NOT-CAMPAIGN (u105)
ERR-DEADLINE-PASSED (u106)
ERR-NOT-OWNER (u107)
ERR-NOT-FUNDED (u108)
ERR-ALREADY-RELEASED (u109)
ERR-NOT-MILESTONE (u110)
ERR-NO-MILESTONE (u111)
```

## Development

This contract is written in Clarity for the Stacks blockchain. For development:

1. Install Clarity tools
2. Deploy using Clarinet or other Stacks deployment tools
3. Test thoroughly before mainnet deployment

## Contributing

[Add contribution guidelines]
