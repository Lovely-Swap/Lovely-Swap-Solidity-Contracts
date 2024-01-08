// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.15;

/**
    An interface to represent the LOVELY DEX token listing.

    Used in:
    - LOVELYFactory;
    - LOVELYCompetition.
 */
interface ILOVELYTokenList {

    /**
        Returns, whether the given token is validated in the DEX.
        The token is validated when the validation amount in the given token is paid.

        @param _token The token to be checked.

		@return Whether the given token is validated in the DEX.
	 */
    function validated(address _token) external view returns (bool);

    function defaultValidationToken() external view returns (address);
}
