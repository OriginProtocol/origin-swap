# Origin SWap

Minimal market maker.

Uses prices for each pair direction that are set by the contract owner.

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
