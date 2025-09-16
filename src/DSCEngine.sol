// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/shared/interfaces/AggregatorV3Interface.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {DSCEngineLogs as Logs} from "./logs/DSCEngineLogs.sol";

/*
 * @title DSCEngine
 * @author Joseph Anyaegbunam
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard {
    // custom errors
    error DSCEngine__TokenAddressesCannotBeZero();
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenADdressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__MintFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    /*//////////////////////////////////////////////////////////////
                                 STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address token => address priceFeed) public s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount))
        public s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) public s_DSCMinted;
    address[] public s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;

    /*//////////////////////////////////////////////////////////////
                                 MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenADdressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        if (dscAddress == address(0)) {
            revert DSCEngine__TokenAddressesCannotBeZero();
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /**
     * @notice Allows users to deposit collateral and mint DSC in one transaction.
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice Allows users to deposit collateral
     * @param tokenCollateralAddress The address of the collateral token to deposit
     * @param amount The amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amount
    )
        public
        moreThanZero(amount)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // get WETH / WBTC / etc from user
        // deposit collateral
        // mint DSC
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amount;
        emit Logs.CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amount
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(
            msg.sender,
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
    }

    /**
     * @notice Allows users to redeem collateral
     * @param tokenCollateralAddress The address of the collateral token to redeem
     * @param amount The amount of collateral to redeem
     */
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amount
    )
        external
        moreThanZero(amount)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // healt factore must be over 1 after redeeming
        _redeemCollateral(
            msg.sender,
            msg.sender,
            tokenCollateralAddress,
            amount
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(
        uint256 amountDscToBurn
    ) public moreThanZero(amountDscToBurn) nonReentrant {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); //TODO: CHECK health factor can't go below 1
    }

    function liquidate(
        address collateral,
        address userToLiquidate,
        uint256 debtToCover
    ) external {
        uint256 startingUserHealthFactor = _healthFactor(userToLiquidate);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // Calculate collateral to seize from the unhealthy user
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;
        // Cap seizure to user's actual collateral balance
        if (
            totalCollateralToRedeem >
            s_collateralDeposited[userToLiquidate][collateral]
        ) {
            totalCollateralToRedeem = s_collateralDeposited[userToLiquidate][
                collateral
            ];
        }

        // Transfer user's collateral to liquidator as reward
        _redeemCollateral(
            userToLiquidate,
            msg.sender,
            collateral,
            totalCollateralToRedeem
        );
        // Update liquidator's collateral balance in the system
        s_collateralDeposited[msg.sender][
            collateral
        ] += totalCollateralToRedeem;

        // Liquidator pays DSC to cover user's debt
        _burnDsc(debtToCover, userToLiquidate, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(userToLiquidate);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Calculates the minimum debt that needs to be covered to make an unhealthy position healthy
     * @param user The address of the user whose position needs to be made healthy
     * @return debtToCover The minimum amount of DSC debt that needs to be covered
     * @dev Returns 0 if the position is already healthy
     * @dev This helps liquidators determine the optimal liquidation amount
     */
    function getDebtToCoverForHealthyPosition(
        address user
    ) external view returns (uint256 debtToCover) {
        uint256 currentHealthFactor = _healthFactor(user);

        // If already healthy, no debt needs to be covered
        if (currentHealthFactor >= MIN_HEALTH_FACTOR) {
            return 0;
        }

        uint256 totalDscMinted = s_DSCMinted[user];
        uint256 collateralValueInUsd = getAccountCollateralValue(user);

        // Calculate the maximum DSC that can be supported by current collateral
        // Formula: maxDsc = (collateralValue * liquidationThreshold) / 100
        uint256 maxDscSupported = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // If current debt is more than what collateral can support,
        // we need to reduce debt to the maximum supported amount
        if (totalDscMinted > maxDscSupported) {
            debtToCover = totalDscMinted - maxDscSupported;
        } else {
            // This shouldn't happen if health factor < 1, but handle edge case
            debtToCover = 0;
        }
    }

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmount
    ) public view returns (uint256) {
        uint256 price = _getPrice(token); // 8 decimals
        uint256 tokenDecimals = IERC20Metadata(token).decimals();
        return
            (usdAmount * (10 ** tokenDecimals)) /
            (price * ADDITIONAL_FEED_PRECISION);
    }

    /*//////////////////////////////////////////////////////////////
                     PRIVATE AND INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates the health factor for a user's position
     * @dev Health factor determines how close a user is to liquidation
     * @dev If health factor < 1e18, the user can be liquidated
     * @dev Formula: (collateralValue * liquidationThreshold / 100) * 1e18 / totalDscMinted
     * @param user The address of the user to calculate health factor for
     * @return The health factor scaled to 1e18 precision (1e18 = 100% healthy, <1e18 = liquidatable)
     */
    function _healthFactor(address user) private view returns (uint256) {
        // Get user's total DSC minted and total collateral value in USD
        (
            uint256 totalDscMinted,
            uint256 totalCollateralValueInUsd
        ) = _getAccountInformation(user);

        return
            _calculateHealthFactor(totalDscMinted, totalCollateralValueInUsd);
    }

    /**
     * @notice Checks if a user's health factor is below the liquidation threshold and reverts if so
     * @dev This function is used as a safety check after operations that could affect health factor
     * @dev Health factor below 1e18 (100%) means the position is undercollateralized and can be liquidated
     * @param user The address of the user whose health factor to check
     * @custom:reverts DSCEngine__BreaksHealthFactor if health factor is below 1e18
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        // Calculate the user's current health factor
        uint256 userHealthFactor = _healthFactor(user);

        // If health factor is below 1e18 (100%), the position is undercollateralized
        // This means the user doesn't have enough collateral to back their minted DSC
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _redeemCollateral(
        address from,
        address to,
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) internal {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit Logs.CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @dev low-level internal funciton, do not call unless the function calling it is checking for health factor being broken
     * @notice Burns DSC tokens from a user's balance
     * @param amountDscToBurn The amount of DSC tokens to burn
     * @param onBehalfOf The address whose DSC balance will be reduced
     * @param from The address that owns the DSC tokens to be burned
     */
    function _burnDsc(
        uint256 amountDscToBurn,
        address onBehalfOf,
        address from
    ) internal {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(from, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        totalCollateralValueInUsd = getAccountCollateralValue(user);
    }

    function _getUsdValue(
        address token,
        uint256 amount
    ) private view returns (uint256) {
        // Convert token amount to USD value with 18 decimals
        // Example: 1 ETH = $2000, user has 1 ETH (1e18 wei)
        // Chainlink price = $2000 * 1e8 = 200000000000 (8 decimals)
        // amount = 1e18 wei (1 ETH with 18 decimals)
        // Result: (200000000000 * 1e18 * 1e10) / 1e18 = 2000e18 ($2000 with 18 decimals)

        uint256 price = _getPrice(token);
        return (price * amount * ADDITIONAL_FEED_PRECISION) / PRECISION;
    }

    /**
     * @notice Gets the latest price of a token from Chainlink price feed
     * @param token The address of the token to get the price for
     * @return The price of the token in USD with 8 decimal precision (Chainlink standard)
     */
    function _getPrice(address token) private view returns (uint256) {
        // Get the price feed contract for this token
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );

        // Get the latest price data from Chainlink
        // We only need the price (second return value), ignore the rest
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // price.staleCheckLatestRoundData();

        // Convert from int256 to uint256 and return
        // Price comes with 8 decimals from Chainlink
        return uint256(price);
    }

    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        // If no DSC is minted, health factor is effectively infinite (very healthy)
        if (totalDscMinted == 0) return type(uint256).max;

        // Apply liquidation threshold (50% means user needs 200% overcollateralization)
        // Example: $1000 collateral * 50 / 100 = $500 effective collateral for health calculation
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // Calculate health factor: adjustedCollateral / totalDscMinted
        // Multiply by PRECISION to maintain 18 decimal precision
        // Example: $500 * 1e18 / $400 DSC = 1.25e18 (125% health factor - safe)
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /*//////////////////////////////////////////////////////////////
                     PUBLIC EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) external pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    /**
     * @notice Gets comprehensive account information for a user
     * @param user The address of the user to get information for
     * @return totalDscMinted The total amount of DSC tokens minted by the user
     * @return totalCollateralValueInUsd The total USD value of the user's collateral with 18 decimal precision
     */
    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    /**
     * @notice Calculates the total USD value of all collateral deposited by a user
     * @param user The address of the user to calculate collateral value for
     * @return totalCollateralValueInUsd The total USD value of the user's collateral with 18 decimal precision
     */
    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount deposited,
        // and map to price feed to get USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
    }

    /**
     * @notice Calculates the USD value of a given amount of tokens
     * @param token The address of the token to get the USD value for
     * @param amount The amount of tokens (in wei, 18 decimals)
     * @return The USD value of the tokens with 18 decimal precision
     */
    function getUsdValue(
        address token,
        uint256 amount
    ) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getMaxCollateralBackedMint(
        address user
    ) public view returns (uint256) {
        (, uint256 totalCollateralValueInUsd) = _getAccountInformation(user);
        return
            (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) /
            LIQUIDATION_PRECISION;
    }

    /**
     * @notice Calculates how much additional DSC a user can safely mint based on their current position
     * @param user The address of the user to calculate additional mintable amount for
     * @return additionalMintable The additional amount of DSC the user can mint without breaking health factor
     * @dev Returns 0 if the user has already minted the maximum amount or is close to liquidation
     */
    function getMaxSafeMint(address user) external view returns (uint256) {
        (
            uint256 totalDscMinted,
            uint256 totalCollateralValueInUsd
        ) = _getAccountInformation(user);

        uint256 maxDscSupported = (totalCollateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        if (maxDscSupported <= totalDscMinted) {
            return 0;
        }

        return maxDscSupported - totalDscMinted;
    }

    /**
     * @notice Calculates the maximum amount of a specific collateral token that can be safely redeemed
     * @notice without breaking the minimum health factor requirement
     * @param tokenCollateralAddress The address of the collateral token to check
     * @param user The address of the user whose position to check
     * @return maxRedeemable The maximum amount of the specified collateral that can be safely redeemed
     * @dev Returns 0 if user has no DSC minted (can redeem all collateral)
     * @dev Returns 0 if user is already at or below minimum collateral needed
     * @dev Formula: Find collateral amount that keeps health factor >= 1e18
     */
    function getMaxRedeemableCollateral(
        address tokenCollateralAddress,
        address user
    ) external view returns (uint256) {
        (
            uint256 totalDscMinted,
            uint256 totalCollateralValueInUsd
        ) = _getAccountInformation(user);

        // If no DSC minted, user can redeem all their collateral
        if (totalDscMinted == 0) {
            return s_collateralDeposited[user][tokenCollateralAddress];
        }

        // Calculate minimum collateral value needed to maintain health factor >= 1e18
        // Formula: minCollateralValue = (totalDscMinted * LIQUIDATION_PRECISION) / LIQUIDATION_THRESHOLD
        uint256 minCollateralValueNeeded = (totalDscMinted *
            LIQUIDATION_PRECISION) / LIQUIDATION_THRESHOLD;

        // If current collateral is already at or below minimum needed, can't redeem any
        if (totalCollateralValueInUsd <= minCollateralValueNeeded) {
            return 0;
        }

        // Calculate excess collateral value that can be safely removed
        uint256 excessCollateralValue = totalCollateralValueInUsd -
            minCollateralValueNeeded;

        // Convert excess USD value back to token amount
        uint256 maxRedeemableInTokens = getTokenAmountFromUsd(
            tokenCollateralAddress,
            excessCollateralValue
        );

        // Cap to user's actual balance of this specific token
        uint256 userBalance = s_collateralDeposited[user][
            tokenCollateralAddress
        ];
        return
            maxRedeemableInTokens > userBalance
                ? userBalance
                : maxRedeemableInTokens;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralBalanceOfUser(
        address token,
        address user
    ) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getYourCollateralBalance(
        address token
    ) external view returns (uint256) {
        return s_collateralDeposited[msg.sender][token];
    }
}
