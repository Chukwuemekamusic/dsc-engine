// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {DSCEngineLogs as Logs} from "src/logs/DSCEngineLogs.sol";

contract DSCEngineTest is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig config;

    address weth;
    address wbtc;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    DeployDSC deployer;
    uint256 deployerKey;

    address public USER = makeAddr("user");
    address liquidator = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    function setUp() public {
        deployer = new DeployDSC();
        (dscEngine, dsc, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey) = config
            .activeNetworkConfig();
        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL);
    }

    modifier skipIfSepolia() {
        if (block.chainid == 11155111) {
            return;
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTION TESTS
    //////////////////////////////////////////////////////////////*/
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsifTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenADdressesAndPriceFeedAddressesMustBeSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*//////////////////////////////////////////////////////////////
                              PRICE TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetUsdValue() public view skipIfSepolia {
        uint256 amount = 2e18;
        // Get the actual ETH price from the price feed to calculate expected USD value
        uint256 ethPrice = uint256(
            MockV3Aggregator(wethUsdPriceFeed).latestAnswer()
        );
        uint256 expectedUsd = (ethPrice * amount * ADDITIONAL_FEED_PRECISION) /
            PRECISION; // Convert 8 decimals to 18 decimals
        uint256 actualUsd = dscEngine.getUsdValue(weth, amount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public view skipIfSepolia {
        uint256 usdAmount = 100 ether;
        uint256 ethPrice = uint256(
            MockV3Aggregator(wethUsdPriceFeed).latestAnswer()
        );
        // uint256 expectedTokenAmount = 0.05 ether;
        uint256 expectedTokenAmount = (usdAmount * PRECISION) /
            (ethPrice * ADDITIONAL_FEED_PRECISION);
        uint256 actualTokenAmount = dscEngine.getTokenAmountFromUsd(
            weth,
            usdAmount
        );
        assertEq(actualTokenAmount, expectedTokenAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TEST
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfCollateralIsNotListed() public {
        ERC20Mock token = new ERC20Mock("MOCK", "MOCK", address(this), 1000e18);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(token), 1000e18);
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testDepositCollateralEmitsEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, false, true);
        emit Logs.CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dscEngine
            .getAccountInformation(USER);
        uint256 expectedDepositAmountInUsd = dscEngine.getUsdValue(
            weth,
            AMOUNT_COLLATERAL
        );
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(
            weth,
            totalCollateralValueInUsd
        );
        console2.log("expectedDepositAmount", expectedDepositAmountInUsd);

        assertEq(totalDscMinted, 0);
        assertEq(totalCollateralValueInUsd, expectedDepositAmountInUsd);
        assertEq(expectedDepositAmount, AMOUNT_COLLATERAL);
    }

    function testDepositCollateralFailsWithZeroAmount() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testDepositCollateralFailsWithNotAllowedToken() public {
        ERC20Mock token = new ERC20Mock(
            "MOCK",
            "MOCK",
            address(this),
            AMOUNT_COLLATERAL
        );
        vm.startPrank(USER);
        token.approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(token), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                               MINT TESTS
    //////////////////////////////////////////////////////////////*/
    function testRevertsIfMintAmountIsZero() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountIsTooHigh() public depositCollateral {
        vm.startPrank(USER);

        // Calculate max safe mint (50% of collateral due to 200% overcollateralization requirement)
        uint256 maxSafeMint = dscEngine.getMaxSafeMint(USER);

        // Try to mint slightly more than the max safe amount
        uint256 tooMuchDsc = maxSafeMint + 1;

        vm.expectRevert();
        dscEngine.mintDsc(tooMuchDsc);
        vm.stopPrank();
    }

    function testMintDsc() public depositCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = 100 ether;
        dscEngine.mintDsc(amountToMint);
        uint256 expectedDscMinted = amountToMint;
        uint256 actualDscMinted = dscEngine.s_DSCMinted(USER);
        assertEq(actualDscMinted, expectedDscMinted);
        vm.stopPrank();
    }

    function testMintDscUpdatesAccountInformation() public depositCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = 100 ether;
        dscEngine.mintDsc(amountToMint);
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dscEngine
            .getAccountInformation(USER);
        assertEq(totalDscMinted, amountToMint);
        assertEq(
            totalCollateralValueInUsd,
            dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL)
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          DEPOSIT AND MINT TESTS
    //////////////////////////////////////////////////////////////*/

    modifier depositCollateralAndMintDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_TO_MINT
        );
        vm.stopPrank();
        _;
    }

    function testDepositCollateralAndMintDsc()
        public
        depositCollateralAndMintDsc
    {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dscEngine
            .getAccountInformation(USER);
        assertEq(totalDscMinted, AMOUNT_TO_MINT);
        assertEq(
            totalCollateralValueInUsd,
            dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL)
        );
    }

    /*//////////////////////////////////////////////////////////////
                          HEALTH_FACTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testHealthFactorIsGoodWhenNoDscMinted() public depositCollateral {
        vm.startPrank(USER);
        uint256 healthFactor = dscEngine.getHealthFactor(USER);
        assertEq(healthFactor, type(uint256).max);
        vm.stopPrank();
    }

    function testHealthFactorCanGoBelowOne()
        public
        depositCollateralAndMintDsc
    {
        vm.startPrank(USER);
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        // Remember, we need $200 at all times if we have $100 of debt

        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 healthFactor = dscEngine.getHealthFactor(USER);
        assert(healthFactor < 1e18);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          REDEEM COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfRedeemAmountIsZero() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfRedeemAmountIsGreaterThanDeposited()
        public
        depositCollateral
    {
        vm.startPrank(USER);
        vm.expectRevert();
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL + 1);
        vm.stopPrank();
    }

    function testRevertsIfHealthFactorIsBroken() public depositCollateral {
        vm.startPrank(USER);
        // Mint 100 DSC
        dscEngine.mintDsc(AMOUNT_TO_MINT);
        // Try to redeem 10 ETH (all collateral) - this should break health factor
        vm.expectRevert();
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanRedeemCollateralWithoutDsc() public depositCollateral {
        vm.startPrank(USER);
        // Deposit some collateral first
        (uint256 totalDscMinted, ) = dscEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);

        uint256 initialBalance = ERC20Mock(weth).balanceOf(USER);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 finalBalance = ERC20Mock(weth).balanceOf(USER);

        assertEq(totalDscMinted, 0);
        assertEq(finalBalance, initialBalance + AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanRedeemPartialCollateral() public depositCollateral {
        vm.startPrank(USER);
        // Mint some DSC first
        uint256 amountToMint = 50 ether;
        dscEngine.mintDsc(amountToMint);

        // Redeem half the collateral - should still maintain healthy ratio
        uint256 redeemAmount = AMOUNT_COLLATERAL / 2;
        uint256 initialBalance = ERC20Mock(weth).balanceOf(USER);

        dscEngine.redeemCollateral(weth, redeemAmount);

        uint256 finalBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(finalBalance, initialBalance + redeemAmount);

        // Check collateral was properly reduced
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dscEngine
            .getAccountInformation(USER);
        uint256 expectedCollateralValue = dscEngine.getUsdValue(
            weth,
            AMOUNT_COLLATERAL - redeemAmount
        );
        assertEq(totalCollateralValueInUsd, expectedCollateralValue);
        assertEq(totalDscMinted, amountToMint);
        vm.stopPrank();
    }

    function testRedeemCollateralEmitsEvent() public depositCollateral {
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, true);
        emit Logs.CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCantRedeemCollateralsWithUnhealthyFactor()
        public
        depositCollateralAndMintDsc
    {
        vm.startPrank(USER);
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 healthFactorAfterCrash = dscEngine.getHealthFactor(USER);

        vm.expectRevert();
        dscEngine.redeemCollateral(weth, 1);

        assert(healthFactorAfterCrash < 1e18);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          BURN DSC TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfBurnAmountIsZero()
        public
        depositCollateralAndMintDsc
    {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.burnDsc(0);
        vm.stopPrank();
    }

    function testCanBurnDsc() public depositCollateralAndMintDsc {
        vm.startPrank(USER);
        uint256 burnAmount = 50 ether;

        // Check initial DSC balance
        (uint256 initialDscMinted, ) = dscEngine.getAccountInformation(USER);
        assertEq(initialDscMinted, AMOUNT_TO_MINT);

        dsc.approve(address(dscEngine), burnAmount);
        dscEngine.burnDsc(burnAmount);

        // Check DSC balance after burn
        (uint256 finalDscMinted, ) = dscEngine.getAccountInformation(USER);
        assertEq(finalDscMinted, AMOUNT_TO_MINT - burnAmount);
        vm.stopPrank();
    }

    function testCanBurnAllDsc() public depositCollateralAndMintDsc {
        vm.startPrank(USER);

        // Approve DSCEngine to spend user's DSC tokens
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);

        // Burn all minted DSC
        dscEngine.burnDsc(AMOUNT_TO_MINT);

        // Check DSC balance is zero
        (uint256 finalDscMinted, ) = dscEngine.getAccountInformation(USER);
        assertEq(finalDscMinted, 0);
        vm.stopPrank();
    }

    function testRevertsIfBurnMoreThanMinted()
        public
        depositCollateralAndMintDsc
    {
        vm.startPrank(USER);
        uint256 burnAmount = AMOUNT_TO_MINT + 1 ether;

        vm.expectRevert();
        dscEngine.burnDsc(burnAmount);
        vm.stopPrank();
    }

    function testBurnDscWithoutDscMinted() public depositCollateral {
        vm.startPrank(USER);

        // Try to burn DSC when none was minted
        vm.expectRevert();
        dscEngine.burnDsc(1 ether);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         LIQUIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testLiquidationRevertsIfHealthFactorIsOk()
        public
        depositCollateralAndMintDsc
    {
        ERC20Mock(weth).mint(liquidator, AMOUNT_COLLATERAL);
        vm.startPrank(liquidator);
        // Health factor should be good initially
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(weth, USER, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testCanLiquidateUnhealthyPosition() public {
        // Setup liquidator FIRST with good collateral and DSC

        ERC20Mock(weth).mint(liquidator, AMOUNT_COLLATERAL);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_TO_MINT
        );
        vm.stopPrank();

        // Setup: User deposits collateral and mints DSC
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_TO_MINT
        );
        vm.stopPrank();

        // NOW crash the ETH price to make USER's position unhealthy
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(18e8); // Crash from $2000 to $18

        // Liquidator executes liquidation
        vm.startPrank(liquidator);
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);
        dscEngine.liquidate(weth, USER, AMOUNT_TO_MINT);
        vm.stopPrank();

        // Verify liquidation worked
        (uint256 userDscMinted, ) = dscEngine.getAccountInformation(USER);
        assertEq(userDscMinted, 0); // User's debt should be cleared
    }

    function testLiquidatorCollateralBalanceUpdatedAfterLiquidation() public {
        // Setup liquidator with collateral and DSC
        ERC20Mock(weth).mint(liquidator, AMOUNT_COLLATERAL);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_TO_MINT
        );
        vm.stopPrank();

        // Setup user with collateral and DSC
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_TO_MINT
        );
        vm.stopPrank();

        // Crash ETH price to make user's position unhealthy
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(18e8); // $2000 -> $18

        // Get liquidator collateral value after price crash but before liquidation
        (, uint256 liquidatorCollateralBeforeLiquidation) = dscEngine
            .getAccountInformation(liquidator);

        // Calculate expected collateral seizure
        uint256 tokenAmountFromDebt = dscEngine.getTokenAmountFromUsd(
            weth,
            AMOUNT_TO_MINT
        );
        uint256 bonusCollateral = (tokenAmountFromDebt * 10) / 100; // 10% bonus
        uint256 totalCollateralToSeize = tokenAmountFromDebt + bonusCollateral;
        uint256 expectedSeizedValue = dscEngine.getUsdValue(
            weth,
            totalCollateralToSeize
        );

        // Execute liquidation
        vm.startPrank(liquidator);
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);
        dscEngine.liquidate(weth, USER, AMOUNT_TO_MINT);
        vm.stopPrank();

        // Verify liquidator's collateral balance increased by the seized amount
        (, uint256 liquidatorCollateralAfterLiquidation) = dscEngine
            .getAccountInformation(liquidator);
        assertEq(
            liquidatorCollateralAfterLiquidation,
            liquidatorCollateralBeforeLiquidation + expectedSeizedValue
        );
    }

    function testGetDebtToCoverForHealthyPosition() public {
        // Setup user with collateral and DSC
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_TO_MINT
        );
        vm.stopPrank();

        // Initially healthy - should return 0
        uint256 debtToCover = dscEngine.getDebtToCoverForHealthyPosition(USER);
        assertEq(debtToCover, 0);

        // Crash ETH price to make position unhealthy
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(18e8); // $2000 -> $18

        // Now should return debt that needs to be covered
        debtToCover = dscEngine.getDebtToCoverForHealthyPosition(USER);

        // Calculate expected debt to cover
        // Collateral value: 10 ETH * $18 = $180
        // Max DSC supported: $180 * 50% = $90
        // Current DSC debt: 100 DSC
        // Debt to cover: 100 - 90 = 10 DSC
        uint256 expectedDebtToCover = 10e18;
        assertEq(debtToCover, expectedDebtToCover);

        // Example: Liquidator can use this to determine optimal liquidation amount
        console2.log("Debt to cover for healthy position:", debtToCover);
        console2.log(
            "This is the minimum DSC needed to make the position healthy"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW AND PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function testGetAccountCollateralValue() public depositCollateral {
        uint256 collateralValue = dscEngine.getAccountCollateralValue(USER);
        assertEq(
            collateralValue,
            dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL)
        );
    }

    function testGetCollateralTokens() public view {
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }
}
