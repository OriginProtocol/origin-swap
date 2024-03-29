// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableOperable} from "./OwnableOperable.sol";
import {IERC20} from "./Interfaces.sol";

contract OSwapBase is OwnableOperable {
    address public constant stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    /**
     * @notice For one `token0` from a Trader, how many `token1` does the pool send.
     * For example, if `token0` is WETH and `token1` is stETH then
     * `traderate0` is the WETH/stETH price.
     * From a Trader's perspective, this is the stETH/WETH buy price.
     * Rate is to 36 decimals (1e36).
     */
    uint256 public traderate0;
    /**
     * @notice For one `token1` from a Trader, how many `token0` does the pool send.
     * For example, if `token0` is WETH and `token1` is stETH then
     * `traderate1` is the stETH/WETH price.
     * From a Trader's perspective, this is the stETH/WETH sell price.
     * Rate is to 36 decimals (1e36).
     */
    uint256 public traderate1;

    /// @dev Maximum operator settable traderate. 1e36
    uint256 internal constant MAX_OPERATOR_RATE = 1005 * 1e33;
    /// @dev Minimum funds to allow operator to price changes
    uint256 public minimumFunds;

    event TraderateChanged(uint256 traderate0, uint256 traderate1);

    constructor(address _token0, address _token1) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        require(IERC20(token0).decimals() == 18);
        require(IERC20(token1).decimals() == 18);
        _setOwner(address(0)); // Revoke owner for implementation contract at deployment
    }

    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible.
     * msg.sender should have already given the OSwap contract an allowance of
     * at least amountIn on the input token.
     *
     * @param inToken Input token.
     * @param outToken Output token.
     * @param amountIn The amount of input tokens to send.
     * @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
     * @param to Recipient of the output tokens.
     */
    function swapExactTokensForTokens(
        IERC20 inToken,
        IERC20 outToken,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external {
        _swapExactTokensForTokens(inToken, outToken, amountIn, amountOutMin, to);
    }

    /**
     * @notice Uniswap V2 Router compatible interface. Swaps an exact amount of
     * input tokens for as many output tokens as possible.
     * msg.sender should have already given the OSwap contract an allowance of
     * at least amountIn on the input token.
     *
     * @param amountIn The amount of input tokens to send.
     * @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
     * @param path The input and output token addresses.
     * @param to Recipient of the output tokens.
     * @param deadline Unix timestamp after which the transaction will revert.
     * @return amounts The input and output token amounts.
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        _inDeadline(deadline);
        require(path.length == 2, "OSwap: Invalid path length");
        IERC20 inToken = IERC20(path[0]);
        IERC20 outToken = IERC20(path[1]);

        uint256 amountOut = _swapExactTokensForTokens(inToken, outToken, amountIn, amountOutMin, to);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    /**
     * @notice Receive an exact amount of output tokens for as few input tokens as possible.
     * msg.sender should have already given the router an allowance of
     * at least amountInMax on the input token.
     *
     * @param inToken Input token.
     * @param outToken Output token.
     * @param amountOut The amount of output tokens to receive.
     * @param amountInMax The maximum amount of input tokens that can be required before the transaction reverts.
     * @param to Recipient of the output tokens.
     */
    function swapTokensForExactTokens(
        IERC20 inToken,
        IERC20 outToken,
        uint256 amountOut,
        uint256 amountInMax,
        address to
    ) external {
        _swapTokensForExactTokens(inToken, outToken, amountOut, amountInMax, to);
    }

    /**
     * @notice Uniswap V2 Router compatible interface. Receive an exact amount of
     * output tokens for as few input tokens as possible.
     * msg.sender should have already given the router an allowance of
     * at least amountInMax on the input token.
     *
     * @param amountOut The amount of output tokens to receive.
     * @param amountInMax The maximum amount of input tokens that can be required before the transaction reverts.
     * @param path The input and output token addresses.
     * @param to Recipient of the output tokens.
     * @param deadline Unix timestamp after which the transaction will revert.
     * @return amounts The input and output token amounts.
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        _inDeadline(deadline);
        require(path.length == 2, "OSwap: Invalid path length");
        IERC20 inToken = IERC20(path[0]);
        IERC20 outToken = IERC20(path[1]);

        uint256 amountIn = _swapTokensForExactTokens(inToken, outToken, amountOut, amountInMax, to);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    function _swapExactTokensForTokens(
        IERC20 inToken,
        IERC20 outToken,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) internal returns (uint256 amountOut) {
        uint256 price;
        if (inToken == token0) {
            require(outToken == token1, "OSwap: Invalid token");
            price = traderate0;
        } else if (inToken == token1) {
            require(outToken == token0, "OSwap: Invalid token");
            price = traderate1;
        } else {
            revert("OSwap: Invalid token");
        }
        amountOut = amountIn * price / 1e36;
        require(amountOut >= amountOutMin, "OSwap: Insufficient output amount");

        // Transfer the input tokens from the caller to this OSwap contract
        inToken.transferFrom(msg.sender, address(this), amountIn);

        // Transfer the output tokens to the recipient
        uint256 transferAmountOut = _calcTransferAmount(address(outToken), amountOut);
        outToken.transfer(to, transferAmountOut);
    }

    function _swapTokensForExactTokens(
        IERC20 inToken,
        IERC20 outToken,
        uint256 amountOut,
        uint256 amountInMax,
        address to
    ) internal returns (uint256 amountIn) {
        uint256 price;
        if (inToken == token0) {
            require(outToken == token1, "OSwap: Invalid token");
            price = traderate0;
        } else if (inToken == token1) {
            require(outToken == token0, "OSwap: Invalid token");
            price = traderate1;
        } else {
            revert("OSwap: Invalid token");
        }
        amountIn = ((amountOut * 1e36) / price) + 1; // +1 to always round in our favor
        require(amountIn <= amountInMax, "OSwap: Excess input amount");

        // Transfer the input tokens from the caller to this OSwap contract
        inToken.transferFrom(msg.sender, address(this), amountIn);

        // Transfer the output tokens to the recipient
        uint256 transferAmountOut = _calcTransferAmount(address(outToken), amountOut);
        outToken.transfer(to, transferAmountOut);
    }

    /**
     * @notice Calculate transfer amount for outToken.
     * Due to internal stETH mechanics required for rebasing support,
     * in most cases stETH transfers are performed for the value of 1 wei less than passed to transfer method.
     * Larger transfer amounts can be 2 wei less.
     */
    function _calcTransferAmount(address outToken, uint256 amount) internal pure returns (uint256 transferAmount) {
        // Add 2 wei if transferring stETH
        transferAmount = outToken == stETH ? amount + 2 : amount;
    }

    function _inDeadline(uint256 deadline) internal view {
        require(deadline >= block.timestamp, "OSwap: Deadline expired");
    }

    /**
     * @notice Set exchange rates from an operator account
     * @param buyT1 The buy price of Token 1 (t0 -> t1), denominated in Token 0. 1e36
     * @param sellT1 The sell price of Token 1 (t1 -> t0), denominated in Token 0. 1e36
     */
    function setPrices(uint256 buyT1, uint256 sellT1) external onlyOperatorOrOwner {
        uint256 _traderate0 = 1e72 / sellT1; // base (t0) -> token (t1)
        uint256 _traderate1 = buyT1; // token (t1) -> base (t0)
        // Limit funds and loss when called by operator
        if (msg.sender == _operator()) {
            uint256 currentFunds = token0.balanceOf(address(this)) + token1.balanceOf(address(this));
            require(currentFunds > minimumFunds, "OSwap: Too much loss");
            require(_traderate0 <= MAX_OPERATOR_RATE, "OSwap: Traderate too high");
            require(_traderate1 <= MAX_OPERATOR_RATE, "OSwap: Traderate too high");
        }
        _setTraderates(_traderate0, _traderate1);
    }

    /**
     * @notice Sets the minimum funds to allow operator price changes
     */
    function setMinimumFunds(uint256 _minimumFunds) external onlyOwner {
        minimumFunds = _minimumFunds;
    }

    function _setTraderates(uint256 _traderate0, uint256 _traderate1) internal {
        require((1e72 / (_traderate0)) > _traderate1, "OSwap: Price cross");
        traderate0 = _traderate0;
        traderate1 = _traderate1;

        emit TraderateChanged(_traderate0, _traderate1);
    }

    /**
     * @notice Rescue token.
     */
    function transferToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }

    /**
     * @notice Rescue ETH.
     */
    function transferEth(address to, uint256 amount) external onlyOwner {
        (bool success,) = to.call{value: amount}(new bytes(0));
        require(success, "OSwap: ETH transfer failed");
    }
}
