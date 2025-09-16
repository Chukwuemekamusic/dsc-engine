// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

/**
 * @title PriceVolatilityHandler
 * @notice Handler for price volatility integration tests
 * @dev Includes price manipulation functions that can break protocol invariants
 * @dev This is intentionally separate from the main fuzz Handler to isolate price crash scenarios
 */
contract PriceVolatilityHandler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    ERC20Mock public weth;
    ERC20Mock public wbtc;

    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;

    address[] public usersWithDepositedCollateral;
    address[] public usersWithDSC;
    mapping(address user => bool depositedCollateral)
        public userDepositedCollateral;
    mapping(address user => bool mintedDSC) public userMintedDSC;

    // Ghost variables for tracking
    uint256 public priceUpdateCount;
    uint256 public timesMintIsCalled;
    uint256 public timesDepositIsCalled;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(
            dscEngine.getCollateralTokenPriceFeed(address(weth))
        );
        btcUsdPriceFeed = MockV3Aggregator(
            dscEngine.getCollateralTokenPriceFeed(address(wbtc))
        );
    }

    /**
     * @notice Simulates normal user deposit behavior
     */
    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        if (!userDepositedCollateral[msg.sender]) {
            usersWithDepositedCollateral.push(msg.sender);
            userDepositedCollateral[msg.sender] = true;
        }
        timesDepositIsCalled++;
    }

    /**
     * @notice Simulates normal user minting behavior
     */
    function mintDsc(uint256 amountDscToMint, uint256 addressSeed) public {
        address sender = _getSenderFromSeed(addressSeed);
        if (sender == address(0)) {
            return;
        }

        amountDscToMint = bound(amountDscToMint, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(sender);

        uint256 maxDscToMint = dscEngine.getMaxSafeMint(sender);
        amountDscToMint = bound(amountDscToMint, 0, maxDscToMint);
        if (amountDscToMint == 0) {
            vm.stopPrank();
            return;
        }

        dscEngine.mintDsc(amountDscToMint);
        vm.stopPrank();

        if (!userMintedDSC[sender]) {
            usersWithDSC.push(sender);
            userMintedDSC[sender] = true;
        }
        timesMintIsCalled++;
    }

    /**
     * @notice Simulates extreme price volatility scenarios
     * @dev This function can break protocol invariants and is intended for stress testing
     */
    function updateCollateralPrice(
        uint256 collateralSeed,
        uint96 newPrice
    ) public {
        // Allow extreme price ranges to test protocol resilience
        // Min: $0.01, Max: $1M (covers from crash to extreme bull market)
        newPrice = uint96(bound(newPrice, 1e6, 1_000_000e8)); // 8 decimals for Chainlink

        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        MockV3Aggregator priceFeed = collateral == weth
            ? ethUsdPriceFeed
            : btcUsdPriceFeed;

        int256 newPriceInt = int256(uint256(newPrice));
        priceFeed.updateAnswer(newPriceInt);

        console2.log("Price updated for", collateral == weth ? "WETH" : "WBTC");
        console2.log("New price:", uint256(newPriceInt));

        priceUpdateCount++;
    }

    /**
     * @notice Simulates gradual price decline (more realistic than sudden crash)
     */
    function gradualPriceDecrease(
        uint256 collateralSeed,
        uint256 decreasePercent
    ) public {
        // Bound decrease to 1-50% to simulate realistic market movements
        decreasePercent = bound(decreasePercent, 1, 50);

        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        MockV3Aggregator priceFeed = collateral == weth
            ? ethUsdPriceFeed
            : btcUsdPriceFeed;

        (, int256 currentPrice, , , ) = priceFeed.latestRoundData();
        int256 newPrice = currentPrice -
            (currentPrice * int256(decreasePercent)) /
            100;

        // Ensure price doesn't go below $0.01
        if (newPrice < 1e6) {
            newPrice = 1e6;
        }

        priceFeed.updateAnswer(newPrice);

        console2.log(
            "Gradual decrease for",
            collateral == weth ? "WETH" : "WBTC"
        );
        console2.log("Decreased by", decreasePercent, "%");
        console2.log("New price:", uint256(newPrice));

        priceUpdateCount++;
    }

    /**
     * @notice Attempts to liquidate an unhealthy position
     */
    function liquidateUser(uint256 userSeed, uint256 collateralSeed) public {
        if (usersWithDSC.length == 0) return;

        address userToLiquidate = usersWithDSC[userSeed % usersWithDSC.length];
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        uint256 healthFactor = dscEngine.getHealthFactor(userToLiquidate);
        if (healthFactor >= dscEngine.getMinHealthFactor()) {
            return; // User is healthy, can't liquidate
        }

        uint256 debtToCover = dscEngine.getDebtToCoverForHealthyPosition(
            userToLiquidate
        );
        if (debtToCover == 0) return;

        // Mint DSC to liquidator to cover the debt
        vm.startPrank(msg.sender);

        // Give liquidator some collateral first
        collateral.mint(msg.sender, 1000e18);
        collateral.approve(address(dscEngine), 1000e18);
        dscEngine.depositCollateral(address(collateral), 1000e18);

        // Mint DSC to cover the debt
        uint256 maxMint = dscEngine.getMaxSafeMint(msg.sender);
        if (maxMint >= debtToCover) {
            dscEngine.mintDsc(debtToCover);

            // Perform liquidation
            try
                dscEngine.liquidate(
                    address(collateral),
                    userToLiquidate,
                    debtToCover
                )
            {
                console2.log("Successfully liquidated user:", userToLiquidate);
                console2.log("Debt covered:", debtToCover);
            } catch {
                console2.log("Liquidation failed for user:", userToLiquidate);
            }
        }

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getCollateralFromSeed(
        uint256 seed
    ) public view returns (ERC20Mock) {
        if (seed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }

    function _getSenderFromSeed(uint256 seed) public view returns (address) {
        if (usersWithDepositedCollateral.length == 0) {
            return address(0);
        }
        return
            usersWithDepositedCollateral[
                seed % usersWithDepositedCollateral.length
            ];
    }

    /*//////////////////////////////////////////////////////////////
                            GETTERS
    //////////////////////////////////////////////////////////////*/

    function getUsersWithDSC() external view returns (address[] memory) {
        return usersWithDSC;
    }

    function getUsersWithCollateral() external view returns (address[] memory) {
        return usersWithDepositedCollateral;
    }
}
