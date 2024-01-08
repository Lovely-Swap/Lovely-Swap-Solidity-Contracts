// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.15;

import '../Lovelyswap/interfaces/ILovelyswapV2Pair.sol';

/**
    An interface to represent the LOVELY DEX liquidity pool pair token.

    Used in:
    - LovelyswapV2Router02 (patched);
    - LOVELYAuditedRouter;
    - LOVELYFactory.
 */
interface ILOVELYPairToken is ILovelyswapV2Pair {

    /**
        Initializes a pair with the capability to validate the liquidity pool by paying the fee.
        When "_amount" is zero, the pair is automatically validated.

        @param _token The token, in which the validation amount can be paid.
        @param _amount The amount to be paid to validate the pair. Zero for no validation fee.
        @param _fee The commission for operations in this liquidity pool.
        @param __activationBlockNumber The block number, after which the pair becomes available.
     */
    function initializeValidated(
        address _token,
        uint256 _amount,
        uint256 _fee,
        uint256 __activationBlockNumber
    ) external;

    /**
        Returns the fee for this liquidity pool.

        @return The fee for this liquidity pool.
     */
    function getFee() external view returns (uint256);

    /**
        Returns, how many blocks remains till this liquidity pool becomes active.

        @return The requested amount of remaining blocks.
     */
    function getRemainingActivationBlocks() external view returns (uint256);
}
