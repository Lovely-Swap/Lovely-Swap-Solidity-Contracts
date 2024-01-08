// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.15;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Testnet token to simulate "LOVELY" tokens.
 */
contract LOVELYToken is ERC20 {

    // Initial supply. Chosen just for an example.
    uint initialSupply = 1000000 * 1000000000000000000;

    /**
        Creates a new token instance.
     */
    constructor() ERC20("LOVELY Token", "LOVELY") {
        _mint(msg.sender, initialSupply);
    }
}
