// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20, IStETHWithdrawal} from "./Interfaces.sol";
import {Ownable} from "./Ownable.sol";

contract OSwapEthBase is Ownable {
    IERC20 public immutable token;

    /// @dev Price of 1 token in ETH. Used when swapping tokens for ETH. 36 decimals precision.
    uint256 internal traderate0;
    /// @dev Price of 1 ETH in token. Used when swapping ETH for tokens. 36 decimals precision.
    uint256 internal traderate1;

    event TraderateChanged(uint256 traderate0, uint256 traderate1);

    constructor(address _token) {
        token = IERC20(_token);
    }

    /**
     * @notice Swaps an exact amount of ETH for as many output tokens as possible.
     *
     * msg.value The amount of ETH to send.
     * @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
     * @param to Recipient of the output tokens.
     */
    function swapExactETHForTokens(uint256 amountOutMin, address to) external payable {
        uint256 amountOut = msg.value * traderate1 / 1e36;
        require(amountOut >= amountOutMin, "OSwap: Insufficient output amount");

        token.transfer(to, amountOut);
    }

    /**
     * @notice Receive an exact amount of ETH for as few input tokens as possible.
     * msg.sender should have already given the OSwap contract an allowance of at least amountInMax on the input token.
     * If the to address is a smart contract, it must have the ability to receive ETH.
     *
     * @param amountOut The amount of ETH to receive.
     * @param amountInMax The maximum amount of input tokens that can be required before the transaction reverts.
     * @param to Recipient of ETH.
     */
    function swapTokensForExactETH(uint256 amountOut, uint256 amountInMax, address to) external {
        uint256 amountIn = (amountOut * 1e36) / traderate0;
        require(amountIn <= amountInMax, "OSwap: Excess input amount");

        token.transferFrom(msg.sender, address(this), amountIn);
        (bool success,) = to.call{value: amountOut}(new bytes(0));
        require(success, "OSwap: ETH transfer failed");
    }

    /**
     * @notice Swaps an exact amount of tokens for as much ETH as possible.
     * If the to address is a smart contract, it must have the ability to receive ETH.
     *
     * @param amountIn The amount of input tokens to send.
     * @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
     * @param to Recipient of ETH.
     */
    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address to) external {
        uint256 amountOut = amountIn * traderate0 / 1e36;
        require(amountOut >= amountOutMin, "OSwap: Insufficient output amount");

        token.transferFrom(msg.sender, address(this), amountIn);
        (bool success,) = to.call{value: amountOut}(new bytes(0));
        require(success, "OSwap: ETH transfer failed");
    }

    /**
     * @notice Receive an exact amount of tokens for as little ETH as possible.
     * Leftover ETH, if any, is returned to msg.sender
     *
     * msg.value (amountInMax) The maximum amount of ETH that can be required before the transaction reverts.
     * @param amountOut The amount of tokens to receive.
     * @param to Recipient of the output tokens.
     */
    function swapETHForExactTokens(uint256 amountOut, address to) external payable {
        uint256 amountIn = (amountOut * 1e36) / traderate1;
        require(amountIn <= msg.value, "OSwap: Insufficient input amount");

        token.transfer(to, amountOut);

        // Return any leftover ETH to the caller.
        if (msg.value > amountIn) {
            (bool success,) = to.call{value: msg.value - amountIn}(new bytes(0));
            require(success, "OSwap: ETH transfer failed");
        }
    }

    /**
     * @notice Set the exchange rates.
     */
    function setTraderates(uint256 _traderate0, uint256 _traderate1) external onlyOwner {
        require((1e72 / (_traderate0)) > _traderate1, "OSwap: Price cross");
        traderate0 = _traderate0;
        traderate1 = _traderate1;

        emit TraderateChanged(_traderate0, _traderate1);
    }

    /**
     * @notice Rescue token.
     */
    function transferToken(address tokenOut, address to, uint256 amount) external onlyOwner {
        IERC20(tokenOut).transfer(to, amount);
    }

    /**
     * @notice Rescue ETH.
     */
    function transferEth(address to, uint256 amount) external onlyOwner {
        (bool success,) = to.call{value: amount}(new bytes(0));
        require(success, "OSwap: ETH transfer failed");
    }
}
