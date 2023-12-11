// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Vm} from "forge-std/Vm.sol";
import {Test, console2} from "forge-std/Test.sol";

import {IERC20, IOSwap} from "../src/Interfaces.sol";
import {OSwapWEthStEth} from "../src/OSwapWEthStEth.sol";
import {Proxy} from "../src/Proxy.sol";

contract ProxyTest is Test {
    address constant RANDOM_ADDRESS = 0xfEEDBeef00000000000000000000000000000000;

    Proxy proxy;
    IOSwap oswap;

    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address steth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    function setUp() public {
        // Deploy a OSwap contract implementation and a proxy.
        OSwapWEthStEth implementation = new OSwapWEthStEth();
        proxy = new Proxy();
        proxy.initialize(address(implementation), address(this), "");

        oswap = IOSwap(address(proxy));
    }

    function test_upgrade() external {
        oswap.setTraderates(1234, 5678);

        OSwapWEthStEth newImplementation1 = new OSwapWEthStEth();
        proxy.upgradeTo(address(newImplementation1));
        assertEq(proxy.implementation(), address(newImplementation1));

        // Ensure ownership was preserved.
        assertEq(proxy.owner(), address(this));
        assertEq(oswap.owner(), address(this));

        // Ensure the storage was preserved through the upgrade.
        assertEq(oswap.token0(), weth);
        assertEq(oswap.token1(), steth);
    }

    function test_upgradeAndCall() external {
        OSwapWEthStEth newImplementation2 = new OSwapWEthStEth();
        bytes memory data = abi.encodeWithSignature("setTraderates(uint256,uint256)", 4321, 8765);
        proxy.upgradeToAndCall(address(newImplementation2), data);
        assertEq(proxy.implementation(), address(newImplementation2));

        // Ensure ownership was preserved.
        assertEq(proxy.owner(), address(this));
        assertEq(oswap.owner(), address(this));

        // Ensure the storage was preserved through the upgrade.
        assertEq(oswap.token0(), weth);
        assertEq(oswap.token1(), steth);
    }

    function test_setOwner() external {
        assertEq(proxy.owner(), address(this));
        assertEq(oswap.owner(), address(this));

        // Update the owner.
        address newOwner = RANDOM_ADDRESS;
        proxy.setOwner(newOwner);
        assertEq(proxy.owner(), newOwner);
        assertEq(oswap.owner(), newOwner);

        // New owner should be able to call an admin only method.
        vm.prank(newOwner);
        oswap.setTraderates(1, 1);

        // Old owner (this) should now be unauthorized.
        vm.expectRevert("OSwap: Only owner can call this function.");
        oswap.setTraderates(2, 2);
    }

    function test_unauthorizedAccess() external {
        // Proxy's restricted methods.
        vm.prank(RANDOM_ADDRESS);
        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.setOwner(RANDOM_ADDRESS);

        vm.prank(RANDOM_ADDRESS);
        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.initialize(address(this), address(this), "");

        vm.prank(RANDOM_ADDRESS);
        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.upgradeTo(address(this));

        vm.prank(RANDOM_ADDRESS);
        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.upgradeToAndCall(address(this), "");

        // Implementation's restricted methods.
        vm.prank(RANDOM_ADDRESS);
        vm.expectRevert("OSwap: Only owner can call this function.");
        oswap.setOwner(RANDOM_ADDRESS);

        vm.prank(RANDOM_ADDRESS);
        vm.expectRevert("OSwap: Only owner can call this function.");
        oswap.setTraderates(123, 321);
    }
}
