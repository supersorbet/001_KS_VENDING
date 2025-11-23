# VendingMachine - Web3 MMO Item Sales Contract

A secure, gas-optimized contract system for direct sales of in game Items (ERC1155) in a nostalgic MMO. This contract enables configurable sales with flexible payment options, per-address purchase limits, and comprehensive security features.

### Key Features

- ✅ **Secure Sales Management** - Configurable sales with time windows, supply limits, and per-address caps
- ✅ **Flexible Payments** - Support for both ETH and ERC20 token payments
- ✅ **Batch Operations** - Efficient batch purchases with optimized payment aggregation
- ✅ **Gas Optimized** - Uses Solady libraries and efficient data structures (LibBitmap)
- ✅ **Security Hardened** - Overflow protection, reentrancy guards, and comprehensive validation
- ✅ **Modular Architecture** - Clean separation of concerns with reusable libraries
- ✅ **Comprehensive Testing** - Unit, integration, fuzz, and invariant tests

## Project Structure

```
001_KS_VENDING/
├── src/
│   ├── contracts/              # Main contracts
│   │   ├── KSVendingMachineOP_.sol    ✅ Production
│   │   └── KSVendingMachineV056.sol          ⚠️  Older version (excluded)
│   ├── interfaces/             # Contract interfaces
│   │   └── IVendingMachine.sol
│   └── libraries/             # Shared libraries
│       ├── VendingMachineCore.sol    # Errors, types, validation logic
│       └── VendingMachineOps.sol     # Payment & state management
├── test/
│   ├── unit/                   # Unit tests for libraries
│   │   ├── VendingMachineCore.t.sol
│   │   └── VendingMachineOps.t.sol
│   ├── integration/            # Integration tests for main contract
│   │   └── VendingMachine.t.sol
│   ├── fuzz/                  # Fuzz testing (property-based)
│   │   ├── VendingMachineFuzz.t.sol
│   │   ├── VendingMachineFuzzAdvanced.t.sol
│   │   ├── VendingMachineFuzzVisual.t.sol
│   │   └── FuzzVisualDemo.t.sol
│   ├── invariant/             # Invariant testing
│   │   └── VendingMachineInvariant.t.sol
│   └── mocks/                 # Mock contracts for testing
│       ├── MockERC1155.sol
│       └── MockERC20.sol
├── lib/                       # Dependencies (git submodules)
│   ├── solady/                # Gas-optimized Solidity libraries
│   ├── openzeppelin-contracts/ # Standard token interfaces
│   └── forge-std/             # Foundry testing utilities
├── foundry.toml               # Foundry configuration
└── README.md                   # This file
```

## Architecture

The contract has been refactored into a clean, modular architecture:

#### Main Contract (`KSVendingMachineOP_.sol`)
- **Size**: ~750 lines (reduced from ~1020 lines)
- **Purpose**: High-level orchestration and contract interface
- **Responsibilities**: 
  - Public/external function definitions
  - Rich Event emissions

#### Libraries

**`VendingMachineCore.sol`** (~170 lines)
- Custom errors (18 error types)
- Type definitions (`SaleConfig` struct, `MAX_BATCH_SIZE` constant)
- Validation functions (`validatePurchaseVersioned`, `checkForDuplicates`, `isLive`)
- Key generation utilities

**`VendingMachineOps.sol`** (~130 lines)
- Payment handling (`handlePayment` for ETH/ERC20)
- State management (`updatePurchaseStateVersioned` with overflow protection)
- Active sales array management (`addToActiveArray`, `removeFromActiveArray`)

#### Interface (`IVendingMachine.sol`)
- Complete interface definition for all public/external functions
- All events
- Enables easy mocking and alternative implementations

### Benefits of Modular Architecture

1. **Maintainability** - Single responsibility per library, easier bug fixes
2. **Reusability** - Libraries can be used in other contracts
3. **Testability** - Libraries can be tested independently
4. **Readability** - Main contract is ~35% smaller & more precise
5. **Gas Efficiency** - Libraries deployed once and reused

### Sales Configuration

Each sale can be configured with:
- **Price**: Per-token price (uint128)
- **Time Window**: Start and end timestamps (uint64)
- **Supply Limits**: Maximum total supply and per-address limits (uint32)
- **Payment Token**: ETH (address(0)) or any ERC20 token
- **Inventory Check**: Optional verification that contract holds sufficient tokens

### Purchase Methods

1. **Single Purchase** (`purchase`)
   - Purchase a single token type
   - Supports ETH or ERC20 payment
   - Automatic refund for overpayment

2. **Batch Purchase** (`purchaseBatch`)
   - Purchase multiple token types in one transaction
   - Validates all purchases before execution
   - Handles mixed payment types

3. **Optimized Batch Purchase** (`purchaseBatchOptimized`)
   - Aggregates ERC20 payments by token
   - Reduces gas costs for multiple ERC20 purchases
   - One transfer per unique payment token

### Security Features

#### Overflow Protection
- All arithmetic operations checked for overflow
- `totalSold` and `versionedUserPurchases` protected
- `saleVersion` overflow prevention

#### Validation
- Sale must be active and within time window
- Supply limits enforced (total and per-address)
- Inventory verification
- Duplicate token ID detection in batches
- Payment amount validation

#### Race Condition Prevention
- Cannot reconfigure active sales
- Versioned purchase tracking prevents conflicts
- Atomic batch operations

## Installation & Setup

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (latest version)
- Git
- Solidity 0.8.27+

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd 001_KS_VENDING

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test
```

### Configuration

The `foundry.toml` file includes:
- Solidity version: `0.8.28`
- IR optimizer enabled (`via_ir = true`) for stack depth management
- Remappings for dependencies:
  - `solady/=lib/solady/src/`
  - `@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/`
  - `forge-std/=lib/forge-std/src/`

## Usage

### Deployment

1. Deploy the contract:
```solidity
KSVendingMachineOP_Patched vendingMachine = new KSVendingMachineOP_();
```

2. Initialize dependencies:
```solidity
vendingMachine.setKSItems(ksItemsContractAddress);
vendingMachine.setFundsRecipient(fundsRecipientAddress);
```

3. Transfer KSItems to the vending machine contract:
```solidity
ksItems.safeTransferFrom(owner, vendingMachineAddress, tokenId, amount, "");
```

### Configuring a Sale

```solidity
vendingMachine.configSale(
    tokenId,           // Token ID to sell
    1 ether,          // Price per token
    startTimestamp,   // Sale start time
    endTimestamp,     // Sale end time
    1000,             // Maximum supply
    10,               // Max per address (0 = unlimited)
    address(0),       // Payment token (address(0) = ETH)
    true              // Check inventory
);
```

### Making a Purchase

**ETH Payment:**
```solidity
vendingMachine.purchase{value: 1 ether}(tokenId, 1);
```

**ERC20 Payment:**
```solidity
// First approve the contract
erc20Token.approve(vendingMachineAddress, 1 ether);
// Then purchase
vendingMachine.purchase(tokenId, 1);
```

**Batch Purchase:**
```solidity
uint256[] memory tokenIds = new uint256[](2);
tokenIds[0] = 1;
tokenIds[1] = 2;

uint32[] memory quantities = new uint32[](2);
quantities[0] = 5;
quantities[1] = 3;

vendingMachine.purchaseBatch{value: totalCost}(tokenIds, quantities);
```

## API Reference

#### Purchase Functions
- `purchase(uint256 tokenId, uint32 quantity)` - Single purchase
- `purchaseBatch(uint256[] calldata tokenIds, uint32[] calldata quantities)` - Batch purchase
- `purchaseBatchOptimized(uint256[] calldata tokenIds, uint32[] calldata quantities)` - Optimized batch purchase

#### Configuration Functions (Owner Only)
- `configSale(...)` - Configure a new sale
- `setSaleStatus(uint256 tokenId, bool active)` - Activate/deactivate sale
- `updateSaleParams(uint256 tokenId, uint128 newPrice, uint64 newEndTime)` - Update sale parameters
- `setKSItems(address _ksItems)` - Set ERC1155 contract address
- `setFundsRecipient(address _fundsRecipient)` - Set funds recipient
- `setPaused(bool _paused)` - Pause/unpause all purchases

#### View Functions
- `getActiveSaleTokenIds()` - Get all active sale token IDs
- `getActiveSaleCount()` - Get count of active sales
- `getActiveSalesBatch(uint256 startIndex, uint256 count)` - Paginated active sales
- `getLiveSales()` - Get all currently live sales
- `getSaleInfo(uint256 tokenId)` - Get sale information
- `getUserPurchaseInfo(uint256 tokenId, address user)` - Get user purchase info
- `isSaleActive(uint256 tokenId)` - Check if sale is active
- `getRemainingSupply(uint256 tokenId)` - Get remaining supply

### Events

- `SaleConfigured` - Emitted when a sale is configured
- `Purchase` - Emitted on each purchase
- `SaleStatusUpdated` - Emitted when sale status changes
- `SaleParamsUpdated` - Emitted when sale parameters are updated
- `KSItemsUpdated` - Emitted when KSItems address changes
- `FundsRecipientChanged` - Emitted when funds recipient changes
- `SalesPaused` - Emitted when pause state changes
- `BatchTokensWithdrawn` - Emitted on batch token withdrawal
- `ETHWithdrawn` - Emitted on ETH withdrawal
- `ERC20Withdrawn` - Emitted on ERC20 withdrawal

## Security Considerations

- ✅ Integer overflow protection on all arithmetic operations
- ✅ Reentrancy protection via `nonReentrant` modifier
- ✅ Access control via `Ownable` pattern
- ✅ Input validation on all user inputs
- ✅ Batch size limits (`MAX_BATCH_SIZE = 50`)
- ✅ Race condition prevention (versioned sales)
- ✅ Proper initialization checks

### Best Practices

- Always verify sale configuration before purchases
- Use `checkInventory: true` when configuring sales
- Monitor `totalSold` to prevent supply exhaustion
- Set appropriate `maxPerAddress` limits
- Use pause functionality for emergency situations
- Regularly audit funds recipient address

## Optimization

The contract uses several optimization techniques:

- **LibBitmap** - Efficient active sales tracking (1 bit per sale)
- **Packed Storage** - `SaleConfig` struct uses packed storage layout
- **Batch Aggregation** - `purchaseBatchOptimized` reduces ERC20 transfers
- **Efficient Array Management** - O(1) removal from active sales array
- **Solady Libraries** - Gas-optimized implementations

## Testing

The project includes comprehensive testing across multiple levels:

### Test Types

1. **Unit Tests** (`test/unit/`)
   - Test individual library functions
   - Validate error handling and edge cases
   - Test validation logic independently

2. **Integration Tests** (`test/integration/`)
   - Test full contract flows
   - End-to-end purchase scenarios
   - Configuration and state management

3. **Fuzz Tests** (`test/fuzz/`)
   - Property-based testing with random inputs
   - Tests run 256 times with different random values
   - Finds edge cases automatically
   - Visual fuzzing demos available

4. **Invariant Tests** (`test/invariant/`)
   - Ensures properties hold across state changes
   - Tests contract invariants remain true
   - Comprehensive coverage of edge cases

### Running Tests

```bash
# Run all tests
forge test

# Run with gas reporting
forge test --gas-report

# Run specific test suite
forge test --match-path test/integration/
forge test --match-path test/fuzz/

# Run with verbose output
forge test -vvv

# Run fuzz tests with custom iterations
forge test --match-test testFuzz --fuzz-runs 1000

# Generate coverage report
forge coverage

## Contributing

When contributing to this project:

1. Follow the existing code style
2. Add tests for new functionality
3. Update documentation
4. Run `forge test` before submitting
5. Ensure gas optimizations don't compromise security

## License

MIT License - See LICENSE file for details

## Support

For issues, questions, or contributions, please refer to the project repository & organization.


