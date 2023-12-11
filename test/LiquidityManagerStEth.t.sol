// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {LiquidityManagerStEth} from "../src//LiquidityManagerStEth.sol";
import {IERC20, IWEth, IOSwapEth, IStETHWithdrawal, ILiquidityManagerStEth} from "../src/Interfaces.sol";
import {OSwapWEthStEth} from "../src/OSwapWEthStEth.sol";
import {Proxy} from "../src/Proxy.sol";

contract LiquidityManagerTest is Test {
    address constant RANDOM_ADDRESS = 0xfEEDBeef00000000000000000000000000000000;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    IERC20 constant steth = IERC20(STETH);
    IERC20 constant weth = IWEth(WETH);

    IStETHWithdrawal constant withdrawal = IStETHWithdrawal(0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1);

    Proxy proxy;
    ILiquidityManagerStEth manager;

    // Account for stETH rounding errors.
    // See https://docs.lido.fi/guides/lido-tokens-integration-guide/#1-2-wei-corner-case
    uint256 constant ROUNDING = 2;

    function setUp() public {
        vm.label(WETH, "WETH");
        vm.label(STETH, "stETH");

        OSwapWEthStEth implementation = new OSwapWEthStEth();
        proxy = new Proxy();
        proxy.initialize(address(implementation), address(this), "");

        manager = ILiquidityManagerStEth(address(proxy));
        manager.approveStETH();
    }

    /*
     *
     * mintStETH tests
     *
     */
    function test_mintStETHWithEth() external {
        uint256 amount = 1 ether;
        deal(address(manager), amount);

        uint256 managerBalanceEthStart = address(manager).balance;
        uint256 managerBalanceTokenStart = steth.balanceOf(address(manager));

        manager.depositETHForStETH(amount);

        uint256 managerBalanceEthEnd = address(manager).balance;
        uint256 managerBalanceTokenEnd = steth.balanceOf(address(manager));

        assertEq(managerBalanceEthEnd, managerBalanceEthStart - amount, "manager ETH balance");
        assertGe(managerBalanceTokenEnd + ROUNDING, managerBalanceTokenStart + amount, "manager Token balance");
        assertLt(managerBalanceTokenEnd - ROUNDING, managerBalanceTokenStart + amount, "manager Token balance");
    }

    function test_mintStETHWithWEth() external {
        uint256 amount = 1 ether;
        _dealWEth(address(manager), amount);

        uint256 managerBalanceWEthStart = weth.balanceOf(address(manager));
        uint256 managerBalanceTokenStart = steth.balanceOf(address(manager));

        manager.depositWETHForStETH(amount);

        uint256 managerBalanceWEthEnd = weth.balanceOf(address(manager));
        uint256 managerBalanceTokenEnd = steth.balanceOf(address(manager));

        assertEq(managerBalanceWEthEnd, managerBalanceWEthStart - amount, "manager ETH balance");
        assertGe(managerBalanceTokenEnd + ROUNDING, managerBalanceTokenStart + amount, "manager Token balance");
        assertLt(managerBalanceTokenEnd - ROUNDING, managerBalanceTokenStart + amount, "manager Token balance");
    }

    function test_withdrawStEth() external {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        _dealStEth(address(manager), 10 ether);

        uint256[] memory requestIds = manager.requestStETHWithdrawalForETH(amounts);

        assertEq(requestIds.length, 1, "Empty requestIds");
        // Check a NFT representing the withdrawal request was transferred to the proxy contract.
        assertEq(withdrawal.ownerOf(requestIds[0]), address(proxy));
    }

    function test_claimStEthForEth() external {
        // These are couple NFTs that were ready to claim at the block time the tests are run (block number 18715431).
        // Transfer them to the manager.
        uint256 requestId1 = 17048;
        uint256 requestId2 = 17049;
        vm.prank(0xD85A569F3C26f81070544451131c742283360400);
        withdrawal.transferFrom(0xD85A569F3C26f81070544451131c742283360400, address(proxy), requestId1);
        vm.prank(0xD85A569F3C26f81070544451131c742283360400);
        withdrawal.transferFrom(0xD85A569F3C26f81070544451131c742283360400, address(proxy), requestId2);

        // Snapshot ETH balance
        uint256 startBalance = address(proxy).balance;

        // Claim the ETH.
        uint256[] memory requestIds = new uint256[](2);
        requestIds[0] = requestId1;
        requestIds[1] = requestId2;
        manager.claimStETHWithdrawalForETH(requestIds);

        // Ensure the balance increased.
        assertGt(address(proxy).balance, startBalance, "Withdrawal did not increase balance");
    }

    function test_claimStEthForWEth() external {
        // These are couple NFTs that were ready to claim at the block time the tests are run (block number 18715431).
        // Transfer them to the manager.
        uint256 requestId1 = 17048;
        uint256 requestId2 = 17049;
        vm.prank(0xD85A569F3C26f81070544451131c742283360400);
        withdrawal.transferFrom(0xD85A569F3C26f81070544451131c742283360400, address(proxy), requestId1);
        vm.prank(0xD85A569F3C26f81070544451131c742283360400);
        withdrawal.transferFrom(0xD85A569F3C26f81070544451131c742283360400, address(proxy), requestId2);

        // Snapshot WETH balance
        uint256 startBalance = weth.balanceOf(address(manager));

        // Claim the ETH.
        uint256[] memory requestIds = new uint256[](2);
        requestIds[0] = requestId1;
        requestIds[1] = requestId2;
        manager.claimStETHWithdrawalForWETH(requestIds);

        // Ensure the balance increased.
        uint256 endBalance = weth.balanceOf(address(manager));
        assertGt(endBalance, startBalance, "Withdrawal did not increase balance");
    }

    /*
     * Admin tests.
     *
     */
    function test_unauthorizedAccess() external {
        vm.startPrank(RANDOM_ADDRESS);
        uint256[] memory array = new uint256[](1);

        vm.expectRevert("OSwap: Only owner can call this function.");
        manager.approveStETH();

        vm.expectRevert("OSwap: Only owner can call this function.");
        manager.depositETHForStETH(1);

        vm.expectRevert("OSwap: Only owner can call this function.");
        manager.requestStETHWithdrawalForETH(array);

        vm.expectRevert("OSwap: Only owner can call this function.");
        manager.claimStETHWithdrawalForETH(array);

        vm.expectRevert("OSwap: Only owner can call this function.");
        manager.claimStETHWithdrawalForWETH(array);
    }

    function _dealStEth(address to, uint256 amount) internal {
        vm.prank(0x2bf3937b8BcccE4B65650F122Bb3f1976B937B2f); // stETH whale
        steth.transfer(to, amount);
    }

    function _dealWEth(address to, uint256 amount) internal {
        vm.prank(0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E); // WETH whale
        weth.transfer(to, amount);
    }
}
