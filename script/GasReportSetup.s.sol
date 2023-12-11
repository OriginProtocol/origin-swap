// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {IERC20, IOSwap} from "../src/Interfaces.sol";
import {OSwapWEthStEth} from "../src/OSwapWEthStEth.sol";
import {Proxy} from "../src/Proxy.sol";

// Fake aggregator. Allows to simulate warming up storage slots
// like ERC20 balances before calling the OSwap contract.
contract Aggregator {
    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    IOSwap oswap;

    constructor(address _oswap) {
        oswap = IOSwap(_oswap);
        weth.approve(address(oswap), type(uint256).max);
        steth.approve(address(oswap), type(uint256).max);
    }

    function steth_swapExactTokensForTokensWarm() public {
        steth.balanceOf(address(this));
        oswap.swapExactTokensForTokens(steth, weth, 1 ether, 0, address(this));
    }

    function steth_swapExactTokensForTokensCold() public {
        oswap.swapExactTokensForTokens(steth, weth, 1 ether, 0, address(this));
    }

    function steth_balanceOf() public {
        steth.balanceOf(address(this));
    }

    function weth_swapExactTokensForTokensWarm() public {
        weth.balanceOf(address(this));
        oswap.swapExactTokensForTokens(weth, steth, 1 ether, 0, address(this));
    }

    function weth_swapExactTokensForTokensCold() public {
        oswap.swapExactTokensForTokens(weth, steth, 1 ether, 0, address(this));
    }

    function weth_balanceOf() public {
        weth.balanceOf(address(this));
    }

    function empty() public {}
}

contract GasReportSetup is Script {
    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    address constant SWAPPER = 0xfEEDBeef00000000000000000000000000000000;

    Proxy proxy;
    IOSwap oswap;

    // Anvil test account private keys.
    uint256 constant OWNER_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant SWAPPER_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    address owner;
    address swapper;

    function setUp() public {
        owner = vm.addr(OWNER_PK);
        swapper = vm.addr(SWAPPER_PK);

        vm.label(address(weth), "WETH");
        vm.label(address(steth), "stETH");
        vm.label(owner, "OWNER");
        vm.label(swapper, "SWAPPER");

        vm.startBroadcast(OWNER_PK);

        // mint some weth and steth on the owner account.
        (bool success,) = address(steth).call{value: 1000 ether}(new bytes(0));
        require(success, "stETH mint failed");

        (success,) = address(weth).call{value: 1000 ether}(new bytes(0));
        require(success, "WETH wrap failed");

        // Deploy the contracts.
        OSwapWEthStEth implementation = new OSwapWEthStEth();
        proxy = new Proxy();
        proxy.initialize(address(implementation), owner, "");
        oswap = IOSwap(address(proxy));

        Aggregator aggregator = new Aggregator(address(oswap));

        // Set exchange rates.
        oswap.setTraderates(625 * 1e33, 500 * 1e33);

        // Send liquidity to the oswap contract.
        weth.transfer(address(oswap), 100 ether);
        steth.transfer(address(oswap), 100 ether);

        // Send liquidity to the aggregator contract.
        weth.transfer(address(aggregator), 100 ether);
        steth.transfer(address(aggregator), 100 ether);

        vm.stopBroadcast();

        // Approve ERC20 on the swapper.
        vm.startBroadcast(SWAPPER_PK);

        weth.approve(address(oswap), type(uint256).max);
        steth.approve(address(oswap), type(uint256).max);

        vm.stopBroadcast();

        console2.log("============== DEPLOYS");
        console2.log("OSWAP     ", address(oswap));
        console2.log("AGGREGATOR", address(aggregator));

        console2.log("============== BALANCES");
        console2.log("OWNER ETH       ", weth.balanceOf(owner));
        console2.log("OSWAP WETH      ", weth.balanceOf(address(oswap)));
        console2.log("OWNER STETH     ", steth.balanceOf(owner));
        console2.log("OSWAP WETH      ", weth.balanceOf(address(oswap)));
        console2.log("OSWAP STETH     ", steth.balanceOf(address(oswap)));
        console2.log("SWAPPER WETH    ", weth.balanceOf(swapper));
        console2.log("SWAPPER STETH   ", steth.balanceOf(swapper));
        console2.log("AGGREGATOR WETH ", weth.balanceOf(address(aggregator)));
        console2.log("AGGREGATOR STETH", steth.balanceOf(address(aggregator)));
    }

    function run() public {
        console2.log("Done!");
    }
}
