// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {IERC20, IOSwapEth, IStETHWithdrawal} from "../src/Interfaces.sol";
import {OSwapEthStEth} from "../src/OSwapEthStEth.sol";
import {Proxy} from "../src/Proxy.sol";

contract OSwapETHTest is Test {
    address constant RANDOM_ADDRESS = 0xfEEDBeef00000000000000000000000000000000;

    IERC20 steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84); // stETH
    IERC20 token = steth;
    IStETHWithdrawal constant withdrawal = IStETHWithdrawal(0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1);

    Proxy proxy;
    IOSwapEth oswap;

    uint256 constant traderate0 = 500 * 1e33; // 1 token swaps for 0.5 ETH
    uint256 constant traderate1 = 625 * 1e33; // 1 ETH swaps for 0.625 tokens

    // Account for stETH rounding errors.
    // See https://docs.lido.fi/guides/lido-tokens-integration-guide/#1-2-wei-corner-case
    uint256 constant ROUNDING = 2;

    function setUp() public {
        OSwapEthStEth implementation = new OSwapEthStEth();
        proxy = new Proxy();
        proxy.initialize(address(implementation), address(this), "");

        oswap = IOSwapEth(address(proxy));
        oswap.setTraderates(traderate0, traderate1);

        deal(address(oswap), 100 ether);
        _dealToken(address(oswap), 100 ether);

        deal(address(this), 1 ether);
        _dealToken(address(this), 1 ether);

        steth.approve(address(oswap), type(uint256).max);
        vm.label(address(steth), "stETH");
    }

    /*
     * setTraderates tests.
     */
    function test_goodPriceSet() external {
        oswap.setTraderates(992 * 1e33, 1001 * 1e33);
        oswap.setTraderates(1001 * 1e33, 997 * 1e33);
    }

    function test_badPriceSet() external {
        vm.expectRevert(bytes("OSwap: Price cross"));
        oswap.setTraderates(1001 * 1e33, 1001 * 1e33);
        vm.expectRevert(bytes("OSwap: Price cross"));
        oswap.setTraderates(1500 * 1e33, 680 * 1e33);
        vm.expectRevert(bytes("OSwap: Price cross"));
        oswap.setTraderates(680 * 1e33, 1500 * 1e33);
    }

    /*
     *
     * swapExactEthForTokens tests
     *
     */
    function test_swapExactEthForTokens() external {
        _swapExactEthForTokens(1 ether, 625 * 1e15, 625 * 1e15, "");
    }

    function test_swapExactEthForTokens_LowAmoutOutMin() external {
        _swapExactEthForTokens(1 ether, 1 * 1e15, 625 * 1e15, "");
    }

    function test_swapExactEthForTokens_RevertAmountMin() external {
        _swapExactEthForTokens(1 ether, 1 ether, 625 * 1e15, "OSwap: Insufficient output amount");
    }

    function test_swapExactEthForTokens_Zero() external {
        _swapExactEthForTokens(0, 0, 0, "");
    }

    function _swapExactEthForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 expectedOut,
        string memory expectedRevert
    ) internal {
        deal(address(this), amountIn);

        // Snapshot the oswap and caller balances.
        uint256 callerBalanceEthStart = address(this).balance;
        uint256 callerBalanceTokenStart = token.balanceOf(address(this));
        uint256 oswapBalanceEthStart = address(oswap).balance;
        uint256 oswapBalanceTokenStart = token.balanceOf(address(oswap));

        if (bytes(expectedRevert).length != 0) {
            vm.expectRevert(bytes(expectedRevert));
            oswap.swapExactETHForTokens{value: amountIn}(amountOutMin, address(this));
            return;
        }

        oswap.swapExactETHForTokens{value: amountIn}(amountOutMin, address(this));

        // Check the balances.
        uint256 callerBalanceEthEnd = address(this).balance;
        uint256 callerBalanceTokenEnd = token.balanceOf(address(this));
        uint256 oswapBalanceEthEnd = address(oswap).balance;
        uint256 oswapBalanceTokenEnd = token.balanceOf(address(oswap));

        assertEq(callerBalanceEthEnd, callerBalanceEthStart - amountIn, "caller ETH balance");
        assertEq(oswapBalanceEthEnd, oswapBalanceEthStart + amountIn, "oswap ETH balance");

        assertGe(callerBalanceTokenEnd + ROUNDING, callerBalanceTokenStart + expectedOut, "caller Token balance");
        assertLe(callerBalanceTokenEnd - ROUNDING, callerBalanceTokenStart + expectedOut, "caller Token balance");

        assertGe(oswapBalanceTokenEnd + ROUNDING, oswapBalanceTokenStart - expectedOut, "oswap Token balance");
        assertLe(oswapBalanceTokenEnd - ROUNDING, oswapBalanceTokenStart - expectedOut, "oswap Token balance");
    }

    /*
     *
     * swapTokensForExactETH tests
     *
     */
    function test_swapTokensForExactETH() external {
        _swapTokensForExactETH(5 ether, 10 ether, 10 ether, "");
    }

    function test_swapTokensForExactETH_RevertAmountInMax() external {
        _swapTokensForExactETH(5 ether, 1 ether, 10 ether, "OSwap: Excess input amount");
    }

    function test_swapTokensForExactETH_Zero() external {
        _swapTokensForExactETH(0, 0, 0, "");
    }

    function _swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        uint256 expectedAmountIn,
        string memory expectedRevert
    ) internal {
        _dealToken(address(this), amountInMax);

        // Snapshot the oswap and caller balances.
        uint256 callerBalanceEthStart = address(this).balance;
        uint256 callerBalanceTokenStart = token.balanceOf(address(this));
        uint256 oswapBalanceEthStart = address(oswap).balance;
        uint256 oswapBalanceTokenStart = token.balanceOf(address(oswap));

        if (bytes(expectedRevert).length != 0) {
            vm.expectRevert(bytes(expectedRevert));
            oswap.swapTokensForExactETH(amountOut, amountInMax, address(this));
            return;
        }

        oswap.swapTokensForExactETH(amountOut, amountInMax, address(this));

        // Check the balances.
        uint256 callerBalanceEthEnd = address(this).balance;
        uint256 callerBalanceTokenEnd = token.balanceOf(address(this));
        uint256 oswapBalanceEthEnd = address(oswap).balance;
        uint256 oswapBalanceTokenEnd = token.balanceOf(address(oswap));

        assertEq(callerBalanceEthEnd, callerBalanceEthStart + amountOut, "caller ETH balance");
        assertEq(oswapBalanceEthEnd, oswapBalanceEthStart - amountOut, "oswap ETH balance");

        assertGe(callerBalanceTokenEnd + ROUNDING, callerBalanceTokenStart - expectedAmountIn, "caller Token balance");
        assertLe(callerBalanceTokenEnd - ROUNDING, callerBalanceTokenStart - expectedAmountIn, "caller Token balance");

        assertGe(oswapBalanceTokenEnd + ROUNDING, oswapBalanceTokenStart + expectedAmountIn, "oswap Token balance");
        assertLe(oswapBalanceTokenEnd - ROUNDING, oswapBalanceTokenStart + expectedAmountIn, "oswap Token balance");
    }

    /*
     *
     * swapExactTokensForETH tests
     *
     */

    function test_swapExactTokensForETH() external {
        _swapExactTokensForETH(10 ether, 5 ether, 5 ether, "");
    }

    function test_swapExactTokensForETH_RevertAmountOutMin() external {
        _swapExactTokensForETH(10 ether, 20 ether, 5 ether, "OSwap: Insufficient output amount");
    }

    function test_swapExactTokensForETH_Zero() external {
        _swapExactTokensForETH(0, 0, 0, "");
    }

    function _swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 expectedAmountOut,
        string memory expectedRevert
    ) internal {
        _dealToken(address(this), amountIn + 1000);

        // Snapshot the oswap and caller balances.
        uint256 callerBalanceEthStart = address(this).balance;
        uint256 callerBalanceTokenStart = token.balanceOf(address(this));
        uint256 oswapBalanceEthStart = address(oswap).balance;
        uint256 oswapBalanceTokenStart = token.balanceOf(address(oswap));

        if (bytes(expectedRevert).length != 0) {
            vm.expectRevert(bytes(expectedRevert));
            oswap.swapExactTokensForETH(amountIn, amountOutMin, address(this));
            return;
        }

        oswap.swapExactTokensForETH(amountIn, amountOutMin, address(this));

        // Check the balances.
        uint256 callerBalanceEthEnd = address(this).balance;
        uint256 callerBalanceTokenEnd = token.balanceOf(address(this));
        uint256 oswapBalanceEthEnd = address(oswap).balance;
        uint256 oswapBalanceTokenEnd = token.balanceOf(address(oswap));

        assertEq(callerBalanceEthEnd, callerBalanceEthStart + expectedAmountOut, "caller ETH balance");
        assertEq(oswapBalanceEthEnd, oswapBalanceEthStart - expectedAmountOut, "oswap ETH balance");

        assertGe(callerBalanceTokenEnd + ROUNDING, callerBalanceTokenStart - amountIn, "caller Token balance");
        assertLe(callerBalanceTokenEnd - ROUNDING, callerBalanceTokenStart - amountIn, "caller Token balance");

        assertGe(oswapBalanceTokenEnd + ROUNDING, oswapBalanceTokenStart + amountIn, "oswap Token balance");
        assertLe(oswapBalanceTokenEnd - ROUNDING, oswapBalanceTokenStart + amountIn, "oswap Token balance");
    }

    /*
     *
     * swapETHForExactTokens tests
     *
     */
    function test_swapETHForExactTokens() external {
        _swapETHForExactTokens(2 ether, 625 * 1e15, 1 ether, "");
    }

    function test_swapETHForExactTokens_RevertAmountIn() external {
        _swapETHForExactTokens(1 * 1e15, 625 * 1e15, 1 ether, "OSwap: Insufficient input amount");
    }

    function test_swapETHForExactTokens_Zero() external {
        _swapETHForExactTokens(0, 0, 0, "");
    }

    function _swapETHForExactTokens(
        uint256 amountIn,
        uint256 amountOut,
        uint256 expectedAmountIn,
        string memory expectedRevert
    ) internal {
        deal(address(this), amountIn);

        // Snapshot the oswap and caller balances.
        uint256 callerBalanceEthStart = address(this).balance;
        uint256 callerBalanceTokenStart = token.balanceOf(address(this));
        uint256 oswapBalanceEthStart = address(oswap).balance;
        uint256 oswapBalanceTokenStart = token.balanceOf(address(oswap));

        if (bytes(expectedRevert).length != 0) {
            vm.expectRevert(bytes(expectedRevert));
            oswap.swapETHForExactTokens{value: amountIn}(amountOut, address(this));
            return;
        }

        oswap.swapETHForExactTokens{value: amountIn}(amountOut, address(this));

        // Check the balances.
        uint256 callerBalanceEthEnd = address(this).balance;
        uint256 callerBalanceTokenEnd = token.balanceOf(address(this));
        uint256 oswapBalanceEthEnd = address(oswap).balance;
        uint256 oswapBalanceTokenEnd = token.balanceOf(address(oswap));

        assertEq(callerBalanceEthEnd, callerBalanceEthStart - expectedAmountIn, "caller ETH balance");
        assertEq(oswapBalanceEthEnd, oswapBalanceEthStart + expectedAmountIn, "oswap ETH balance");

        assertGe(callerBalanceTokenEnd + ROUNDING, callerBalanceTokenStart + amountOut, "caller Token balance");
        assertLe(callerBalanceTokenEnd - ROUNDING, callerBalanceTokenStart + amountOut, "caller Token balance");

        assertGe(oswapBalanceTokenEnd + ROUNDING, oswapBalanceTokenStart - amountOut, "oswap Token balance");
        assertLe(oswapBalanceTokenEnd - ROUNDING, oswapBalanceTokenStart - amountOut, "oswap Token balance");
    }

    /*
     * Admin tests.
     *
     */
    function test_unauthorizedAccess() external {
        vm.startPrank(RANDOM_ADDRESS);

        // Proxy's restricted methods.
        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.setOwner(RANDOM_ADDRESS);

        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.initialize(address(this), address(this), "");

        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.upgradeTo(address(this));

        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.upgradeToAndCall(address(this), "");

        // Implementation's restricted methods.
        vm.expectRevert("OSwap: Only owner can call this function.");
        oswap.setOwner(RANDOM_ADDRESS);

        vm.expectRevert("OSwap: Only owner can call this function.");
        oswap.setTraderates(123, 321);
    }

    /*
     *
     * Utils
     *
     */
    function _dealToken(address to, uint256 amount) internal {
        require(address(token) == address(steth), "Unsupported token");
        vm.prank(0x2bf3937b8BcccE4B65650F122Bb3f1976B937B2f); // stETH whale
        token.transfer(to, amount);
    }

    receive() external payable {
        console2.log("Received %s ETH!", msg.value);
    }
}
