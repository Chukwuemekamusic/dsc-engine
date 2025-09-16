// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
// // Invariants:
// // protocol must never be insolvent / undercollateralized
// // users cant create stablecoins with a bad health factor
// // total supply of DSC should be less than the total value of all collateral
// // a user should only be able to be liquidated if they have a bad health factor
// // getter view functions should never revert

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    DeployDSC deployer;
    uint256 deployerKey;

    Handler handler;

    function setUp() public {
        deployer = new DeployDSC();
        (dscEngine, dsc, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey) = config
            .activeNetworkConfig();
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply_1()
        public
        view
    {
        // get the value of all the collateral in the protocol
        // compare it to all the debt
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWeth = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtc = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(weth, totalWeth);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtc);

        console2.log("totalSupply", totalSupply);
        console2.log("wethValue", wethValue);
        console2.log("wbtcValue", wbtcValue);
        console2.log("timesMintIsCalled", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNeverRevert() public view {
        dscEngine.getCollateralTokens();
        dscEngine.getDsc();
        dscEngine.getPrecision();
        dscEngine.getAdditionalFeedPrecision();
        dscEngine.getLiquidationThreshold();
        dscEngine.getLiquidationBonus();
        dscEngine.getLiquidationPrecision();
        dscEngine.getMinHealthFactor();
    }
}
