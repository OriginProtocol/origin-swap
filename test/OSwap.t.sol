// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {IERC20, IOSwap} from "../src/Interfaces.sol";
import {OSwapWEthStEth} from "../src/OSwapWEthStEth.sol";
import {Proxy} from "../src/Proxy.sol";

contract OSwapTest is Test {
    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IERC20 BAD_TOKEN = IERC20(makeAddr("bad token"));

    Proxy proxy;
    IOSwap oswap;

    // Account for stETH rounding errors.
    // See https://docs.lido.fi/guides/lido-tokens-integration-guide/#1-2-wei-corner-case
    uint256 constant ROUNDING = 2;

    function setUp() public {
        OSwapWEthStEth implementation = new OSwapWEthStEth();
        proxy = new Proxy();
        proxy.initialize(address(implementation), address(this), "");

        oswap = IOSwap(address(proxy));

        _dealWETH(address(oswap), 100 ether);
        _dealStETH(address(oswap), 100 ether);
        // Contract will trade
        // give us 1 WETH, get 0.625 stETH
        // give us 1 stETH, get 0.5 WETH
        oswap.setTraderates(625 * 1e33, 500 * 1e33);

        weth.approve(address(oswap), type(uint256).max);
        steth.approve(address(oswap), type(uint256).max);
        vm.label(address(weth), "WETH");
        vm.label(address(steth), "stETH");

        // Only fuzz from this address. Big speedup on fork.
        targetSender(address(this));
    }

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

    function test_swapExactTokensForTokens_WETH_TO_STETH() external {
        _swapExactTokensForTokens(weth, steth, 10 ether, 6.25 ether);
    }

    function test_swapExactTokensForTokens_STETH_TO_WETH() external {
        _swapExactTokensForTokens(steth, weth, 10 ether, 5 ether);
    }

    function test_swapTokensForExactTokens_WETH_TO_STETH() external {
        _swapTokensForExactTokens(weth, steth, 10 ether, 6.25 ether);
    }

    function test_swapTokensForExactTokens_STETH_TO_WETH() external {
        _swapTokensForExactTokens(steth, weth, 10 ether, 5 ether);
    }

    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, uint256 expectedOut)
        internal
    {
        if (inToken == weth) {
            _dealWETH(address(this), amountIn + 1000);
        } else {
            _dealStETH(address(this), amountIn + 1000);
        }
        uint256 startIn = inToken.balanceOf(address(this));
        oswap.swapExactTokensForTokens(inToken, outToken, amountIn, 0, address(this));
        assertGt(inToken.balanceOf(address(this)), (startIn - amountIn) - ROUNDING, "In actual");
        assertLt(inToken.balanceOf(address(this)), (startIn - amountIn) + ROUNDING, "In actual");
        assertGt(outToken.balanceOf(address(this)), expectedOut - ROUNDING, "Out actual");
        assertLt(outToken.balanceOf(address(this)), expectedOut + ROUNDING, "Out actual");
    }

    function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, uint256 expectedOut)
        internal
    {
        if (inToken == weth) {
            _dealWETH(address(this), amountIn + 1000);
        } else {
            _dealStETH(address(this), amountIn + 1000);
        }
        uint256 startIn = inToken.balanceOf(address(this));
        oswap.swapTokensForExactTokens(inToken, outToken, expectedOut, 3 * expectedOut, address(this));
        assertGt(inToken.balanceOf(address(this)), (startIn - amountIn) - ROUNDING, "In actual");
        assertLt(inToken.balanceOf(address(this)), (startIn - amountIn) + ROUNDING, "In actual");
        assertGt(outToken.balanceOf(address(this)), expectedOut - ROUNDING, "Out actual");
        assertLt(outToken.balanceOf(address(this)), expectedOut + ROUNDING, "Out actual");
    }

    function test_unauthorizedAccess() external {
        address RANDOM_ADDRESS = 0xfEEDBeef00000000000000000000000000000000;
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

    function test_wrongInTokenExactIn() external {
        vm.expectRevert("OSwap: Invalid token");
        oswap.swapExactTokensForTokens(BAD_TOKEN, steth, 10 ether, 0, address(this));
        vm.expectRevert("OSwap: Invalid token");
        oswap.swapExactTokensForTokens(BAD_TOKEN, weth, 10 ether, 0, address(this));
        vm.expectRevert("OSwap: Invalid token");
        oswap.swapExactTokensForTokens(weth, weth, 10 ether, 0, address(this));
        vm.expectRevert("OSwap: Invalid token");
        oswap.swapExactTokensForTokens(steth, steth, 10 ether, 0, address(this));
    }

    function test_wrongOutTokenExactIn() external {
        vm.expectRevert("OSwap: Invalid token");
        oswap.swapTokensForExactTokens(weth, BAD_TOKEN, 10 ether, 0, address(this));
        vm.expectRevert("OSwap: Invalid token");
        oswap.swapTokensForExactTokens(steth, BAD_TOKEN, 10 ether, 0, address(this));
        vm.expectRevert("OSwap: Invalid token");
        oswap.swapTokensForExactTokens(weth, weth, 10 ether, 0, address(this));
        vm.expectRevert("OSwap: Invalid token");
        oswap.swapTokensForExactTokens(steth, steth, 10 ether, 0, address(this));
    }

    function test_wrongInTokenExactOut() external {
        vm.expectRevert("OSwap: Invalid token");
        oswap.swapTokensForExactTokens(BAD_TOKEN, steth, 10 ether, 0, address(this));
        vm.expectRevert("OSwap: Invalid token");
        oswap.swapTokensForExactTokens(BAD_TOKEN, weth, 10 ether, 0, address(this));
        vm.expectRevert("OSwap: Invalid token");
        oswap.swapTokensForExactTokens(weth, weth, 10 ether, 0, address(this));
        vm.expectRevert("OSwap: Invalid token");
        oswap.swapTokensForExactTokens(steth, steth, 10 ether, 0, address(this));
    }

    function test_wrongOutTokenExactOut() external {
        vm.expectRevert("OSwap: Invalid token");
        oswap.swapTokensForExactTokens(weth, BAD_TOKEN, 10 ether, 0, address(this));
        vm.expectRevert("OSwap: Invalid token");
        oswap.swapTokensForExactTokens(steth, BAD_TOKEN, 10 ether, 0, address(this));
        vm.expectRevert("OSwap: Invalid token");
        oswap.swapTokensForExactTokens(weth, weth, 10 ether, 0, address(this));
        vm.expectRevert("OSwap: Invalid token");
        oswap.swapTokensForExactTokens(steth, steth, 10 ether, 0, address(this));
    }

    function test_collectTokens() external {
        oswap.transferToken(address(weth), address(this), weth.balanceOf(address(oswap)));
        assertGt(weth.balanceOf(address(this)), 50 ether);
        assertEq(weth.balanceOf(address(oswap)), 0);

        oswap.transferToken(address(steth), address(this), steth.balanceOf(address(oswap)));
        assertGt(steth.balanceOf(address(this)), 50 ether);
        assertLt(steth.balanceOf(address(oswap)), 3);
    }

    function _dealStETH(address to, uint256 amount) internal {
        vm.prank(0x2bf3937b8BcccE4B65650F122Bb3f1976B937B2f);
        steth.transfer(to, amount);
    }

    function _dealWETH(address to, uint256 amount) internal {
        deal(address(weth), to, amount);
    }

    // Slow on fork
    // function invariant_nocrossed_trading_exact_eth() external {
    //     uint256 sumBefore = weth.balanceOf(address(oswap)) + steth.balanceOf(address(oswap));
    //     _dealWETH(address(this), 1 ether);
    //     oswap.swapExactTokensForTokens(weth, steth, weth.balanceOf(address(oswap)), 0, address(this));
    //     oswap.swapExactTokensForTokens(steth, weth, steth.balanceOf(address(oswap)), 0, address(this));
    //     uint256 sumAfter = weth.balanceOf(address(oswap)) + steth.balanceOf(address(oswap));
    //     assertGt(sumBefore, sumAfter, "Lost money swapping");
    // }
}
