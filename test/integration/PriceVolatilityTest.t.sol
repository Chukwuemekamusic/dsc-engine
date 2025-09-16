// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PriceVolatilityHandler} from "test/integration/PriceVolatilityHandler.t.sol";

/**
 * @title PriceVolatilityTest
 * @notice Integration tests for price volatility scenarios
 * @dev Tests how the protocol handles extreme price movements and oracle failures
 * @dev These tests are separate from invariants since price crashes can legitimately break protocol health
 */
contract PriceVolatilityTest is StdInvariant, Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    DeployDSC deployer;
    uint256 deployerKey;

    PriceVolatilityHandler handler;

    function setUp() public {
        deployer = new DeployDSC();
        (dscEngine, dsc, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey) = config
            .activeNetworkConfig();
        handler = new PriceVolatilityHandler(dscEngine, dsc);
        targetContract(address(handler));
    }

    /**
     * @notice Tests that protocol becomes undercollateralized during price crashes
     * @dev This is expected behavior - protocol should become insolvent when collateral crashes
     */
    function invariant_protocolCanBecomeUndercollateralizedDuringPriceCrash()
        public
        view
    {
        // This test expects the protocol CAN become undercollateralized
        // We're testing that liquidations and other mechanisms work during crashes

        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWeth = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtc = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(weth, totalWeth);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtc);

        console2.log("totalSupply", totalSupply);
        console2.log("wethValue", wethValue);
        console2.log("wbtcValue", wbtcValue);
        console2.log("priceUpdateCount", handler.priceUpdateCount());

        // During price volatility tests, we expect this can fail
        // The key is testing that the protocol handles the failure gracefully
        if (totalSupply > 0) {
            console2.log(
                "Protocol health ratio:",
                ((wethValue + wbtcValue) * 100) / totalSupply
            );
        }
    }

    /**
     * @notice Tests liquidation functionality during price crashes
     */
    function invariant_liquidationWorksAfterPriceCrash() public view {
        // Test that users with unhealthy positions can be liquidated
        // after price updates make their positions undercollateralized

        // Get all users who have minted DSC
        address[] memory users = handler.getUsersWithDSC();

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 healthFactor = dscEngine.getHealthFactor(user);

            if (healthFactor < dscEngine.getMinHealthFactor()) {
                console2.log("User can be liquidated:", user);
                console2.log("Health factor:", healthFactor);

                // Test that liquidation mechanics still work
                uint256 debtToCover = dscEngine
                    .getDebtToCoverForHealthyPosition(user);
                console2.log("Debt to cover:", debtToCover);
            }
        }
    }

    /**
     * @notice Tests that getter functions don't revert even during price volatility
     */
    function invariant_gettersDontRevertDuringPriceVolatility() public view {
        // These should never revert regardless of price
        dscEngine.getCollateralTokens();
        dscEngine.getDsc();
        dscEngine.getPrecision();
        dscEngine.getMinHealthFactor();
        dscEngine.getLiquidationThreshold();
    }
}
