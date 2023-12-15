// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {IERC20} from "../src/Interfaces.sol";
import {OSwapWEthStEth} from "../src/OSwapWEthStEth.sol";
import {Proxy} from "../src/Proxy.sol";

contract OSwapTest is Test {
    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IERC20 BAD_TOKEN = IERC20(makeAddr("bad token"));

    address operator = makeAddr("operator");

    Proxy proxy;
    OSwapWEthStEth oswap;

    // Account for stETH rounding errors.
    // See https://docs.lido.fi/guides/lido-tokens-integration-guide/#1-2-wei-corner-case
    uint256 constant ROUNDING = 2;

    function setUp() public {
        OSwapWEthStEth implementation = new OSwapWEthStEth();
        proxy = new Proxy();
        proxy.initialize(address(implementation), address(this), "");

        oswap = OSwapWEthStEth(payable(proxy));

        _dealWETH(address(oswap), 100 ether);
        _dealStETH(address(oswap), 100 ether);
        // Contract will trade
        // give us 1 WETH, get 0.625 stETH
        // give us 1 stETH, get 0.5 WETH
        oswap.setPrices(500 * 1e33, 1600000000000000000000000000000000000);
        // Set operator
        oswap.setOperator(operator);

        weth.approve(address(oswap), type(uint256).max);
        steth.approve(address(oswap), type(uint256).max);
        vm.label(address(weth), "WETH");
        vm.label(address(steth), "stETH");

        // Only fuzz from this address. Big speedup on fork.
        targetSender(address(this));
    }

    function test_goodPriceSet() external {
        oswap.setPrices(992 * 1e33, 1001 * 1e33);
        oswap.setPrices(1001 * 1e33, 1004 * 1e33);
    }

    function test_badPriceSet() external {
        vm.expectRevert(bytes("OSwap: Price cross"));
        oswap.setPrices(90 * 1e33, 89 * 1e33);
        vm.expectRevert(bytes("OSwap: Price cross"));
        oswap.setPrices(72, 70);
        vm.expectRevert(bytes("OSwap: Price cross"));
        oswap.setPrices(1005 * 1e33, 1000 * 1e33);
    }

    function test_realistic_swaps() external {
        vm.prank(operator);
        oswap.setPrices(997 * 1e33, 998 * 1e33);
        _swapExactTokensForTokens(steth, weth, 10 ether, 9.97 ether);
        _swapExactTokensForTokens(weth, steth, 10 ether, 10020040080160320641);
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
        uint256 startOut = outToken.balanceOf(address(this));
        oswap.swapExactTokensForTokens(inToken, outToken, amountIn, 0, address(this));
        assertGt(inToken.balanceOf(address(this)), (startIn - amountIn) - ROUNDING, "In actual");
        assertLt(inToken.balanceOf(address(this)), (startIn - amountIn) + ROUNDING, "In actual");
        assertGt(outToken.balanceOf(address(this)), startOut + expectedOut - ROUNDING, "Out actual");
        assertLt(outToken.balanceOf(address(this)), startOut + expectedOut + ROUNDING, "Out actual");
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

        vm.expectRevert("OSwap: Only operator or owner can call this function.");
        oswap.setPrices(123, 321);
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

    /* Operator Tests */

    function test_setOperator() external {
        oswap.setOperator(address(this));
        assertEq(oswap.operator(), address(this));
    }

    function test_nonOwnerCannotSetOperator() external {
        vm.expectRevert("OSwap: Only owner can call this function.");
        vm.prank(operator);
        oswap.setOperator(operator);
    }

    function test_setMinimumFunds() external {
        oswap.setMinimumFunds(100 ether);
        assertEq(oswap.minimumFunds(), 100 ether);
    }

    function test_setGoodCheckedTraderates() external {
        vm.prank(operator);
        oswap.setPrices(992 * 1e33, 2000 * 1e33);
        assertEq(oswap.traderate0(), 500 * 1e33);
        assertEq(oswap.traderate1(), 992 * 1e33);
    }

    function test_setBadCheckedTraderates() external {
        vm.prank(operator);
        vm.expectRevert("OSwap: Traderate too high");
        oswap.setPrices(1010 * 1e33, 1020 * 1e33);
        vm.prank(operator);
        vm.expectRevert("OSwap: Traderate too high");
        oswap.setPrices(993 * 1e33, 994 * 1e33);
    }

    function test_checkTraderateFailsMinimumFunds() external {
        uint256 currentFunds = oswap.token0().balanceOf(address(oswap)) + oswap.token1().balanceOf(address(oswap));
        oswap.setMinimumFunds(currentFunds + 100);

        vm.prank(operator);
        vm.expectRevert("OSwap: Too much loss");
        oswap.setPrices(992 * 1e33, 1001 * 1e33);
    }

    function test_checkTraderateWorksMinimumFunds() external {
        uint256 currentFunds = oswap.token0().balanceOf(address(oswap)) + oswap.token1().balanceOf(address(oswap));
        oswap.setMinimumFunds(currentFunds - 100);

        vm.prank(operator);
        oswap.setPrices(992 * 1e33, 1001 * 1e33);
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
