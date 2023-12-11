// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OSwapEthBase} from "./OSwapEthBase.sol";
import {LiquidityManagerStEth} from "./LiquidityManagerStEth.sol";

contract OSwapEthStEth is OSwapEthBase, LiquidityManagerStEth {
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    constructor() OSwapEthBase(STETH) {}
}
