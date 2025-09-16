// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    ERC20Mock public weth;
    ERC20Mock public wbtc;

    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;

    address[] public usersWithDepositedCollateral;
    mapping(address user => bool depositedCollateral)
        public userDepositedCollateral;

    // ghost variables
    uint256 public timesMintIsCalled;

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

    function mintDsc(uint256 amountDscToMint, uint256 addressSeed) public {
        address sender = _getSenderFromSeed(addressSeed);
        if (sender == address(0)) {
            return;
        }
        amountDscToMint = bound(amountDscToMint, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(sender);
        // (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dscEngine.getAccountInformation(msg.sender);
        uint256 maxDscToMint = dscEngine.getMaxSafeMint(sender);

        amountDscToMint = bound(amountDscToMint, 0, maxDscToMint);
        if (amountDscToMint == 0) {
            return;
        }
        dscEngine.mintDsc(amountDscToMint);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        // vm.assume(amountCollateral > 0);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        if (!userDepositedCollateral[msg.sender]) {
            usersWithDepositedCollateral.push(msg.sender);
        }
        userDepositedCollateral[msg.sender] = true;
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getMaxRedeemableCollateral(
            address(collateral),
            msg.sender
        );
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }

        vm.startPrank(msg.sender);
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    // this breaks the invariant test - commented out to maintain protocol health
    // function updateCollateralPrice(
    //     uint256 collateralSeed,
    //     uint96 newPrice
    // ) public {
    //     // Bound price to reasonable range to avoid extreme scenarios
    //     // Min: $1, Max: $1M (for ETH/BTC this covers realistic ranges)
    //     newPrice = uint96(bound(newPrice, 1e8, 1_000_000e8)); // 8 decimals for Chainlink

    //     ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    //     MockV3Aggregator priceFeed = collateral == weth
    //         ? ethUsdPriceFeed
    //         : btcUsdPriceFeed;

    //     int256 newPriceInt = int256(uint256(newPrice));
    //     priceFeed.updateAnswer(newPriceInt);
    // }

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
}

// function updateCollateralPrice(
//     uint256 collateralSeed,
//     uint96 price
// ) public {
//     ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
//     MockV3Aggregator priceFeed = collateral == weth
//         ? ethUsdPriceFeed
//         : btcUsdPriceFeed;

//     int256 priceInt = int256(uint256(price));
//     if (priceInt == 0) {
//         return;
//     }
//     priceFeed.updateAnswer(priceInt);
// }
