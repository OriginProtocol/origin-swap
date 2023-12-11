// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {IERC20, IOSwap} from "../src/Interfaces.sol";
import {OSwapWEthStEth} from "../src/OSwapWEthStEth.sol";
import {Proxy} from "../src/Proxy.sol";

interface IAggregator {
    function steth_swapExactTokensForTokensWarm() external;
    function steth_swapExactTokensForTokensCold() external;
    function steth_balanceOf() external;

    function weth_swapExactTokensForTokensWarm() external;
    function weth_swapExactTokensForTokensCold() external;
    function weth_balanceOf() external;

    function empty() external;
}

contract GasReportRun is Script {
    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    address constant SWAPPER = 0xfEEDBeef00000000000000000000000000000000;

    Proxy proxy;
    IOSwap oswap;
    IAggregator aggregator;

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

        oswap = IOSwap(vm.envAddress("OSWAP"));
        aggregator = IAggregator(vm.envAddress("AGGREGATOR"));

        console2.log("OSWAP=", address(oswap));
        console2.log("AGGREGATOR=", address(aggregator));
    }

    function run() public {
        vm.startBroadcast(SWAPPER_PK);

        /*
        oswap.swapExactTokensForTokens(steth, weth, 1 ether, 0, swapper);
        oswap.swapExactTokensForTokens(weth, steth, 1 ether, 0, swapper);

        oswap.swapTokensForExactTokens(steth, weth, 1 ether, 2 ether, swapper);
        oswap.swapTokensForExactTokens(weth, steth, 1 ether, 2 ether, swapper);
        */
        aggregator.steth_swapExactTokensForTokensCold();
        aggregator.steth_swapExactTokensForTokensWarm();
        aggregator.steth_balanceOf();

        aggregator.weth_swapExactTokensForTokensCold();
        aggregator.weth_swapExactTokensForTokensWarm();
        aggregator.weth_balanceOf();

        aggregator.empty();

        vm.stopBroadcast();
    }
}
