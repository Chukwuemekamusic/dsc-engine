// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DSCEngineLogs
 * @author Joseph Anyaegbunam
 * @notice Library containing event definitions for the DSC Engine contract
 * @dev This library centralizes all events used by DSCEngine for better organization and reusability
 */
library DSCEngineLogs {
    event CollateralDeposited(address indexed user, address indexed tokenCollateralAddress, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed tokenCollateralAddress, uint256 amount
    );
}
