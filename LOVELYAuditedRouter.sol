// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.15;

import "./interfaces/ILOVELYPairToken.sol";
import "./LOVELYRouter.sol";
import './Lovelyswap/v2-periphery-patched/LovelyswapV2Library.sol';
import "./interfaces/ILOVELYAddressFilter.sol";

/**
    @title The DEX's router, which can be enabled to collect data for the trades oracle.

    The trades oracle serves for tracking the trades history on-chain.
    Such tracking might be necessary for particular events, which can be researched or analytics
    for which may be used to build additional business processes.


    The overall process to use the trades oracle:
    1. An event is started.
    2. This event creates an instance of the audited router.
    3. The whole system or a part of the system is switched to using this router.
    4. Data is collected.
    5. The event is finished.
    6. The whole system or a part of the system switches back to the usual router.
    7. Collected data is analyzed on-chain.

    The outcome of such behavior is ability to proof the trades data on-chain.
 */
contract LOVELYAuditedRouter is LOVELYRouter {

    // The tracked token.
    address private target;

    /**
        The list of tracked  addresses.
     */
    address[] public addresses;

    /**
        Contains volumes for each tracked address.
     */
    mapping(address => uint256) public volumes;

    /**
        Creates the audited router with the trades oracle.

        @param theFactory The DEX factory, to be able to interact with the DEX.
        @param theWETH The WETH token address, to be able to create a router.
        @param theTarget A token, for which the audition will be performed.
     */
    constructor(address theFactory, address theWETH, address theTarget) LOVELYRouter(theFactory, theWETH) {
        require(address(0) != theFactory && address(0) != theWETH && address(0) != theTarget, "LOVELY DEX: ZERO_ADDRESS");
        target = theTarget;
    }

    /**
        Returns the given amount of top-volume tracked addresses.

        @param count The amount of addresses to be returned.
        @param theContextIdentifier The identifier of a context for which to perform the filter.
        @param theFilter The entity to filter addresses which can be taken.
     */
    function topAddresses(uint256 count, uint256 theContextIdentifier, ILOVELYAddressFilter theFilter) external view returns (address[] memory) {

        require(0 < addresses.length, "LOVELY DEX: NO_PLAYERS");

        // While requesting more top addresses, than ones, who were using this router, reduce the requested amount to
        // the factually available count.
        if (count > addresses.length) {
            count = addresses.length;
        }

        address[] memory top = new address[](count);
        address[] memory processed = addresses;

        for (uint256 i = 0; i < count; i++) {

            uint256 biggest = i;
            uint256 biggestValue = 0;
            for (uint256 k = i; k < addresses.length; k++) {
                address targetAddress = addresses[k];
                if (
                    biggestValue < volumes[targetAddress] &&
                    (address(0x0) == address(theFilter) || theFilter.included(theContextIdentifier, targetAddress))) {
                    biggest = k;
                    biggestValue = volumes[targetAddress];
                }
            }

            // 3-glass exchange :)
            address glass = processed[i];
            processed[i] = processed[biggest];
            processed[biggest] = glass;

            top[i] = processed[i];
        }

        return top;
    }

    /**
        Returns the length of the tracked addresses list.
     */
    function addressesLength() external view returns (uint256) {
        return addresses.length;
    }

    /**
        An empty implementation to reduce the contract size.
     */
    function addLiquidity(
        address,
        address,
        uint,
        uint,
        uint,
        uint,
        address,
        uint
    ) external virtual override returns (uint amountA, uint amountB, uint liquidity) {
        return (0, 0, 0);
    }

    /**
        An empty implementation to reduce the contract size.
     */
    function addLiquidityETH(
        address,
        uint,
        uint,
        uint,
        address,
        uint
    ) external virtual override payable returns (uint amountToken, uint amountETH, uint liquidity) {
        return (0, 0, 0);
    }

    /**
        Internally hooks into the "_swap" router's call to record necessary data.

        The volume is accumulated for the given target token.
     */
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal override {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = LovelyswapV2Library.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? LovelyswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            ILovelyswapV2Pair(LovelyswapV2Library.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );

            // Track into the audition log
            // (if no volume before, but new volume is more than zero)
            // (and if either input or output tokens match the target for this audition)
            if ((target == input || target == output) && 0 == volumes[to] && (0 < amount0Out + amount1Out)) {
                addresses.push(to);
            }

            volumes[to] += target == input ? amounts[i] : target == output ? amounts[i + 1] : 0;
        }
    }

    /**
        Internally hooks into the "_swapSupportingFeeOnTransferTokens" router's call to record necessary data.

        The volume is accumulated for the given target token.
     */
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal override {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = LovelyswapV2Library.sortTokens(input, output);
            ILOVELYPairToken pair = ILOVELYPairToken(LovelyswapV2Library.pairFor(factory, input, output));
            uint fee = pair.getFee();
            uint amountInput;
            uint amountOutput;
            {// scope to avoid stack too deep errors
                (uint reserve0, uint reserve1,) = pair.getReserves();
                (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
                uint256 balance = IERC20(input).balanceOf(address(pair));
                amountInput = balance - reserveInput;
                amountOutput = LovelyswapV2Library.getAmountOut(amountInput, reserveInput, reserveOutput, fee);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? LovelyswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));

            // Track into the audition log
            // (if no volume before, but new volume is more than zero)
            // (and if either input or output tokens match the target for this audition)
            if ((target == input || target == output) && 0 == volumes[to] && (0 < amount0Out + amount1Out)) {
                addresses.push(to);
            }

            volumes[to] += target == input ? amountInput : target == output ? amountOutput : 0;
        }
    }
}
