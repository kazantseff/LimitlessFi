// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "./shared/Test.sol";
import "../src/market/MarketStorage.sol";

contract MarketTest is Test {
    function setUp() public {
        deployVaultAndMarket();
        vm.startPrank(owner);
        vault.setUtilizationPercentage(8000);
        market.setMinimumPositionSize(1e17); // 0.1 ETH
        market.setMaxLeverage(15);
        market.setLiquidationFeePercentage(100);
        vm.stopPrank();

        // Deposit 10_000 usdc into vault, so there is liquidity for borrowing
        _depositInVault(aliceDepositor, 10000e8);
        // Mint trader 10_000 USDC
        usdc.mint(trader, 10000e8);
        // Approve traders usdc to market
        vm.prank(trader);
        usdc.approve(address(market), type(uint256).max);
    }

    // I have to make a call to market here, instead of using an internal _openPosition function,
    // becasue vm.expectRevert won't work properly otherwise
    function testOpenPositionRevertsIfBelowMinimumSize()
        public
        asAccount(trader)
    {
        vm.expectRevert(InvalidPositionSize.selector);
        market.openPosition(5e16, 500e8, true);
    }

    function testOpenPositionRevertsIfExceedsMaxLeverage()
        public
        asAccount(trader)
    {
        vm.expectRevert(PositionExceedsMaxLeverage.selector);
        market.openPosition(1e18, 100e8, true);
    }

    function testOpenPositionRevertsIfPositionAlreadyOpen()
        public
        asAccount(trader)
    {
        market.openPosition(1e18, 1000e8, true);
        vm.expectRevert("Position is already open");
        market.openPosition(1e18, 1000e8, true);
    }

    function testOpenPositionIncreasesOpenInterestLong()
        public
        asAccount(trader)
    {
        market.openPosition(1e18, 1000e8, true);
        assertEq(2000e18, market.openInterestUSDLong());
        assertEq(1e18, market.openInterstInUnderlyingLong());
    }

    function testOpenPositionIncreasesOpenInterestShort()
        public
        asAccount(trader)
    {
        market.openPosition(1e18, 1000e8, false);
        assertEq(2000e18, market.openInterestUSDShort());
        assertEq(1e18, market.openInterstInUnderlyingShort());
    }

    function testOpenPositionSetsPositionCorrectly() public asAccount(trader) {
        market.openPosition(1e18, 1000e8, true);
        (
            uint256 collateral,
            uint256 size,
            uint256 averagePrice,
            bool isLong,
            uint256 lastTimestampAccrued
        ) = market.userPosition(trader);

        assertEq(collateral, 1000e8);
        assertEq(size, 1e18);
        assertEq(averagePrice, 2000e18);
        assertEq(isLong, true);
        assertEq(lastTimestampAccrued, block.timestamp);
    }

    function testOpenPositionTransfersCollateralFromUser()
        public
        asAccount(trader)
    {
        uint256 oldMarketBalance = usdc.balanceOf(address(market));
        assertEq(usdc.balanceOf(trader), 10000e8);
        market.openPosition(1e18, 1000e8, true);
        assertEq(usdc.balanceOf(trader), 9000e8);
        assertEq(usdc.balanceOf(address(market)), oldMarketBalance + 1000e8);
    }

    function testOpenPositionRevertsIfNotEnoughLiquidity()
        public
        asAccount(trader)
    {
        // In setUp Alice deposited 10_000 USDC, with utilizationPercentage being 80%, only 8000 USDC can be used
        // Openning position of 2ETH with 1000 USDC as collateral, so 3000 USDC is taken from LP
        market.openPosition(2e18, 1000e8, true);
        vm.expectRevert(NotEnoughLiquidity.selector);
        // 6000 usdc in interest - 1000 USDC collateral = 5000 USDc taken from LP
        market.increasePosition(3e18, 1000e8);
    }
}
