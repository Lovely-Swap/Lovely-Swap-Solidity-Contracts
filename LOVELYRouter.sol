// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.15;

import "./Lovelyswap/v2-periphery-patched/LovelyswapV2Router02.sol";

/**
    The default DEX router based on the Lovelyswap V2 router.
 */
contract LOVELYRouter is LovelyswapV2Router02 {

    /**
        Creates a new default routers instance.

        @param theFactory The DEX factory to be attached to the router.
        @param theWETH The WETH address to be used in the DEX.
     */
    constructor(address theFactory, address theWETH) LovelyswapV2Router02(theFactory, theWETH) {
    }
}
