# Origin Swap

Optimized swap contracts for specific high volume stable pairs.

# Mainnet deployment
- stETH/WETH: [0x85B78AcA6Deae198fBF201c82DAF6Ca21942acc6](https://etherscan.io/address/0x85B78AcA6Deae198fBF201c82DAF6Ca21942acc6)

# Swap interface
```
function swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, uint256 amountOutMin, address to) external;
function swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 amountOut, uint256 amountInMax, address to) external;
```
More details about arguments [here](https://github.com/OriginProtocol/origin-swap/blob/513c39ffe38d68f472f01a10abe0310501124178/src/OSwapBase.sol#L21).

# Development

## Install

```
foundryup
forge install
forge compile
```

## Running tests

All tests are fork tests against the actual WETH and STETH contract

```
forge test --fork-url="$PROVIDER_URL" --fork-block-number=18715431 --gas-report
```

## Running gas report scripts
In a terminal, run anvil
```
anvil --fork-url="$PROVIDER_URL" --fork-block-number=18715431
```

In another terminal, run the gas report scripts:
```
forge script script/GasReportSetup.s.sol --broadcast --rpc-url http://localhost:8545
export OSWAP=<OSwap deploy address from the logs>
export AGGREGATOR=<Aggregator deploy address from the logs>
forge script script/GasReportRun.s.sol --broadcast --rpc-url http://localhost:8545
```
