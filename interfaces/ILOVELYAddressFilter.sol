// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.15;

/**
    An interface for entities, capable to filter a list of matching
    addresses.
 */
interface ILOVELYAddressFilter {

    /**
        For a given address, returns, whether it should be included.

        @param _identifier The identifier for making a projection within the data source context.
        @param _address The address to be checked.
     */
    function included(uint256 _identifier, address _address) external view returns (bool);
}
