# DSC Engine - Decentralized Stablecoin Protocol

A minimal, decentralized stablecoin protocol built with Solidity and Foundry. This protocol maintains a 1:1 USD peg through algorithmic mechanisms and over-collateralization.

## 📋 Table of Contents
- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Installation](#installation)
- [Usage](#usage)
- [Testing](#testing)
- [Contract Addresses](#contract-addresses)
- [Security](#security)
- [Contributing](#contributing)

## 🎯 Overview

DSC Engine is an algorithmic stablecoin protocol similar to DAI, but with key differences:
- **No governance** - Fully decentralized
- **No fees** - Zero protocol fees
- **Crypto-collateralized** - Backed only by WETH and WBTC
- **Over-collateralized** - Maintains >200% collateralization ratio
- **USD Pegged** - 1 DSC = $1 USD

### Key Properties
- **Exogenously Collateralized**: Backed by external crypto assets (WETH, WBTC)
- **Dollar Pegged**: Maintains 1:1 peg with USD through market mechanisms
- **Algorithmically Stable**: No human intervention required for stability

## ✨ Features

### Core Functionality
- **Deposit Collateral**: Deposit WETH/WBTC as collateral
- **Mint DSC**: Mint stablecoins against collateral (up to 50% LTV)
- **Redeem Collateral**: Withdraw collateral while maintaining health factor
- **Burn DSC**: Burn stablecoins to improve position or exit
- **Liquidations**: Liquidate unhealthy positions for 10% bonus

### Advanced Features
- **Health Factor Monitoring**: Real-time position health tracking
- **Price Feed Integration**: Chainlink oracle price feeds
- **Liquidation Protection**: Automatic liquidation when health factor < 1
- **Gas Optimized**: Efficient contract design
- **Emergency Functions**: Comprehensive error handling

## 🏗 Architecture

### Core Contracts

#### DSCEngine.sol
The main protocol contract handling all core functionality:
```solidity
// Key Functions
depositCollateral(address tokenCollateralAddress, uint256 amount)
mintDsc(uint256 amountDscToMint)
redeemCollateral(address tokenCollateralAddress, uint256 amount)
liquidate(address collateral, address user, uint256 debtToCover)
```

#### DecentralizedStableCoin.sol
ERC20 stablecoin token with controlled minting/burning:
```solidity
contract DecentralizedStableCoin is ERC20Burnable, Ownable
```

### Supporting Contracts

#### Libraries
- **OracleLib.sol**: Chainlink price feed interactions and staleness checks

#### Logging
- **DSCEngineLogs.sol**: Centralized event definitions

### Project Structure
```
src/
├── DSCEngine.sol              # Main protocol logic
├── DecentralizedStableCoin.sol # ERC20 stablecoin token
├── libraries/
│   └── OracleLib.sol         # Oracle helper functions
└── logs/
    └── DSCEngineLogs.sol     # Event definitions

script/
├── DeployDSC.s.sol           # Deployment script
└── HelperConfig.s.sol        # Network configuration

test/
├── unit/
│   └── DSCEngineTest.t.sol   # Unit tests
├── fuzz/
│   ├── InvariantsTest.t.sol  # Invariant tests
│   └── Handler.t.sol         # Fuzz test handler
├── integration/
│   ├── PriceVolatilityTest.t.sol    # Price volatility tests
│   └── PriceVolatilityHandler.t.sol # Price volatility handler
└── mocks/
    ├── ERC20Mock.sol         # Mock ERC20 token
    └── MockV3Aggregator.sol  # Mock Chainlink aggregator
```

## 🚀 Installation

### Prerequisites
- [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Setup
```bash
# Clone the repository
git clone https://github.com/yourusername/dsc-engine
cd dsc-engine

# Install dependencies
forge install

# Build the project
forge build
```

### Dependencies
- OpenZeppelin Contracts
- Chainlink Contracts
- Foundry Standard Library

## 💼 Usage

### Deployment

#### Local Deployment
```bash
# Start local blockchain
anvil

# Deploy to local network
forge script script/DeployDSC.s.sol --rpc-url http://localhost:8545 --private-key $PRIVATE_KEY --broadcast
```

#### Testnet Deployment
```bash
# Deploy to Sepolia
forge script script/DeployDSC.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
```

### Interacting with the Protocol

#### Using Cast Commands

**Deposit Collateral:**
```bash
cast send $DSC_ENGINE "depositCollateral(address,uint256)" $WETH_ADDRESS 1000000000000000000 --private-key $PRIVATE_KEY
```

**Mint DSC:**
```bash
cast send $DSC_ENGINE "mintDsc(uint256)" 500000000000000000000 --private-key $PRIVATE_KEY
```

**Check Health Factor:**
```bash
cast call $DSC_ENGINE "getHealthFactor(address)" $USER_ADDRESS
```

#### Key Parameters
- **Liquidation Threshold**: 50% (200% overcollateralization required)
- **Liquidation Bonus**: 10%
- **Minimum Health Factor**: 1.0 (1e18)

### Important Functions

#### View Functions
```solidity
getHealthFactor(address user) → uint256
getAccountCollateralValue(address user) → uint256
getMaxSafeMint(address user) → uint256
getMaxRedeemableCollateral(address token, address user) → uint256
getDebtToCoverForHealthyPosition(address user) → uint256
```

#### State-Changing Functions
```solidity
depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint)
redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
```

## 🧪 Testing

This project includes comprehensive testing with multiple strategies:

### Test Categories

#### Unit Tests
```bash
forge test --match-path "test/unit/*" -vv
```

#### Fuzz Tests
```bash
forge test --match-path "test/fuzz/*" -vv
```

#### Invariant Tests
```bash
forge test --mt invariant_ -vv
```

#### Integration Tests (Price Volatility)
```bash
forge test --match-path "test/integration/*" -vv
```

### Key Invariants Tested
1. **Protocol Solvency**: Total collateral value ≥ Total DSC supply
2. **User Health**: Users cannot mint DSC with bad health factors
3. **Liquidation Logic**: Only unhealthy users can be liquidated
4. **Getter Reliability**: View functions never revert

### Test Configuration
```toml
# foundry.toml
[invariant]
runs = 1000
depth = 128
fail_on_revert = true
```

### Coverage Report
```bash
forge coverage
```

### Gas Reporting
```bash
forge test --gas-report
```

## 📊 Contract Addresses

### Mainnet
> ⚠️ **Not yet deployed to mainnet**

### Sepolia Testnet
> ⚠️ **Update with actual deployment addresses**

```
DSCEngine: 0x...
DecentralizedStableCoin: 0x...
WETH Price Feed: 0x...
WBTC Price Feed: 0x...
```

## 🔐 Security

### Security Measures
- **Reentrancy Protection**: All external calls protected with `nonReentrant`
- **Access Control**: Proper ownership and permission management
- **Price Feed Security**: Chainlink oracle integration with staleness checks
- **Health Factor Enforcement**: Strict collateralization requirements
- **Liquidation Incentives**: Economic incentives for position maintenance

### Audits
> ⚠️ **This protocol has not been audited. Use at your own risk.**

### Known Limitations
1. **Oracle Dependency**: Relies on Chainlink price feeds
2. **Collateral Risk**: Subject to WETH/WBTC price volatility
3. **Smart Contract Risk**: Potential bugs in contract logic
4. **Liquidation Risk**: Possible liquidation cascades during market stress

### Security Best Practices
- Always check your health factor before transactions
- Monitor collateral prices and market conditions
- Never deposit more than you can afford to lose
- Understand liquidation mechanics

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Run the test suite (`forge test`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Development Guidelines
- Follow Solidity best practices and style guide
- Maintain >95% test coverage
- Include comprehensive NatSpec documentation
- Ensure all invariant tests pass
- Add integration tests for new features

### Code Style
This project uses:
- Solidity ^0.8.20
- Foundry for development and testing
- OpenZeppelin contracts for standard implementations

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Contact & Support

- **Author**: Joseph Anyaegbunam
- **GitHub**: [Your GitHub Profile]
- **Email**: [Your Email]

## 🙏 Acknowledgments

- Inspired by MakerDAO's DSS system
- Built with Foundry and OpenZeppelin
- Price feeds powered by Chainlink
- Community feedback and contributions

---

⚠️ **Disclaimer**: This is experimental software. Use at your own risk. Never deposit funds you cannot afford to lose.
