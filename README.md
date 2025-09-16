# DSC Engine - Over-Collateralized Stablecoin

A decentralized stablecoin protocol built with Solidity and Foundry. Users can deposit crypto collateral (WETH/WBTC) to mint DSC tokens in an over-collateralized system.

## 🎯 Overview

**DSC Engine** is an over-collateralized stablecoin protocol inspired by MakerDAO. Users deposit cryptocurrency as collateral to mint DSC stablecoins, with strict collateralization requirements and liquidation mechanisms to maintain system health.

### Key Features
- **Over-Collateralized**: Requires 200%+ collateralization (50% max LTV)
- **Crypto-Backed**: Accepts WETH and WBTC as collateral
- **Liquidation System**: 10% bonus for liquidating unhealthy positions
- **No Governance**: Minimal, algorithmic design
- **Price Feeds**: Integrated with Chainlink oracles

## 🏗 How It Works

1. **Deposit Collateral**: Users deposit WETH or WBTC as collateral
2. **Mint DSC**: Users can mint DSC tokens up to 50% of their collateral value
3. **Health Factor**: System tracks each user's collateralization ratio (health factor)
4. **Liquidations**: If health factor < 1.0, anyone can liquidate the position for a 10% bonus

## 🔧 Core Functions

```solidity
// Deposit collateral to back DSC
depositCollateral(address tokenCollateralAddress, uint256 amount)

// Mint DSC against your collateral
mintDsc(uint256 amountDscToMint)

// Withdraw collateral (if health factor stays >1)
redeemCollateral(address tokenCollateralAddress, uint256 amount)

// Liquidate unhealthy positions
liquidate(address collateral, address user, uint256 debtToCover)

// Check position health
getHealthFactor(address user) returns (uint256)
```

## 📁 Project Structure

```
src/
├── DSCEngine.sol              # Main protocol contract
├── DecentralizedStableCoin.sol # ERC20 DSC token
└── libraries/OracleLib.sol    # Chainlink price feed helpers

test/
├── unit/                      # Unit tests
├── fuzz/                      # Fuzz & invariant tests
└── integration/               # Integration tests

script/                        # Deployment scripts
```

## 🚀 Quick Start

```bash
# Clone and setup
git clone https://github.com/josephanyaegbunam/dsc-engine
cd dsc-engine
forge install
forge build

# Run tests
forge test

# Deploy locally
anvil
forge script script/DeployDSC.s.sol --rpc-url http://localhost:8545 --private-key $PRIVATE_KEY --broadcast
```

## 🧪 Testing Highlights

This project showcases comprehensive DeFi testing strategies:

### Test Types
- **Unit Tests**: Core function testing
- **Fuzz Tests**: Random input validation
- **Invariant Tests**: Protocol-wide invariants that must always hold
- **Integration Tests**: Price volatility and liquidation scenarios

### Key Invariants
- Total collateral value ≥ Total DSC minted
- Users can only mint with healthy positions
- Only unhealthy positions can be liquidated

```bash
forge test --match-path "test/unit/*"        # Unit tests
forge test --match-path "test/fuzz/*"        # Fuzz tests
forge test --mt invariant_                   # Invariant tests
forge test --match-path "test/integration/*" # Integration tests
```

## 💡 Technical Highlights

- **Solidity ^0.8.20** with modern patterns and gas optimizations
- **Comprehensive testing** including invariant and integration tests
- **Chainlink price feed integration** with staleness protection
- **Reentrancy guards** and proper access control
- **Mathematical precision** handling for DeFi calculations

## 🔐 Key Considerations

- This is an **educational project** demonstrating DeFi protocol development
- **Over-collateralized system** - not capital efficient but safer
- **No active price stabilization** - DSC value depends on market confidence
- Uses **Chainlink oracles** for price data
- Includes **liquidation mechanisms** to maintain system health

---

Built with ❤️ by **Joseph Anyaegbunam** | [GitHub](https://github.com/josephanyaegbunam)
