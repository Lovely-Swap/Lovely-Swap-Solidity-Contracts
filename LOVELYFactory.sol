// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.15;

import "./interfaces/ILOVELYPairToken.sol";
import "./Lovelyswap/v2-core-patched/LovelyswapV2Factory.sol";
import "./LOVELYPairToken.sol";
import "./LOVELYTokenList.sol";

/**
    The customized LovelyswapV2Factory, containing appropriate DEX business logic updates.
 */
contract LOVELYFactory is LovelyswapV2Factory {

    /**
        The default value for the validation amount to be paid while validating the liquidity pool.
     */
    uint private defaultValidationAmount;

    /**
        The DEX's main token.
        While set, new add operations will work only with liquidity pools containing this token.
     */
    address private mainToken;

    /**
        A reference to the token list to check for listed and validated tokens which are allowed in the DEX.
     */
    LOVELYTokenList private tokenList;

    /**
        Triggered then the default validation amount is set.

        @param _value The new default validation amount.
     */
    event SetDefaultValidationAmount(uint _value);

    /**
        Triggered, when a new main DEX token is set.

        @param _value The new main DEX token.
     */
    event SetMainToken(address _value);

    /**
        Creates a new DEX factory instance.
     */
    constructor() LovelyswapV2Factory(msg.sender) {
        tokenList = new LOVELYTokenList(msg.sender);
    }

    /**
        Returns the current default validation amount value.
     */
    function getDefaultValidationAmount() external view returns (uint) {
        return defaultValidationAmount;
    }

    /**
        Sets the default validation amount.
        Which is a minimum value to be paid while validating tokens upon listing them.

        @param _value The new default validation amount.
     */
    function setDefaultValidationAmount(uint _value) external {

        require(msg.sender == feeToSetter, 'LOVELY DEX: FORBIDDEN');

        defaultValidationAmount = _value;

        emit SetDefaultValidationAmount(_value);
    }

    /**
        Sets the main DEX token, bringing respective limitations.

        @param _value The new main DEX token.
     */
    function setMainToken(address _value) external {

        require(msg.sender == feeToSetter, 'LOVELY DEX: FORBIDDEN');

        mainToken = _value;

        emit SetMainToken(_value);
    }

    /**
        Returns a reference to the token list.
     */
    function getTokenList() external view returns (LOVELYTokenList) {
        return tokenList;
    }

    /**
        Creates a market pair.

        @param tokenA The first token of a pair.
        @param tokenB The second token of a pair.
        @param tokenC The token in which the validation amount should be paid.
        @param validationAmount The amount to be deposited to validate the pair.
        @param fee A fee to be applied while swapping in this liquidity pool.

        @return pair The resulting pair.
     */
    function createValidatedPair(address tokenA, address tokenB, address tokenC, uint validationAmount, uint fee) external returns (address pair) {

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        address defaultValidationToken = ILOVELYTokenList(tokenList).defaultValidationToken();
        // Single check is sufficient
        require(token0 != address(0), 'LOVELY DEX: ZERO_ADDRESS');

        require(tokenA != tokenB, 'LOVELY DEX: IDENTICAL_ADDRESSES');
        require(tokenList.validated(tokenA), "LOVELY DEX: FIRST_NOT_VALIDATED");
        require(tokenList.validated(tokenB), "LOVELY DEX: SECOND_NOT_VALIDATED");
        require(tokenList.validated(tokenC), "LOVELY DEX: THIRD_NOT_VALIDATED");
        require(tokenC == defaultValidationToken, "LOVELY DEX: NOT VALIDATION TOKEN");
        require(msg.sender == feeToSetter || validationAmount == defaultValidationAmount, "LOVELY DEX: FACTORY_VALIDATION_AMOUNT");
        require(mainToken == address(0) || tokenA == mainToken || tokenB == mainToken, "LOVELY DEX: MAIN_TOKEN_CONSTRAINT");

        // Single check is sufficient
        require(getPair[token0][token1] == address(0), 'LOVELY DEX: PAIR_EXISTS');

        bytes memory bytecode = type(LOVELYPairToken).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ILOVELYPairToken(pair).initialize(token0, token1);

        // Desired activation block number
        uint firstActivationBlockNumber = tokenList.activationBlockNumberFor(tokenA);
        uint secondActivationBlockNumber = tokenList.activationBlockNumberFor(tokenB);
        uint activationBlockNumber = firstActivationBlockNumber > secondActivationBlockNumber ? firstActivationBlockNumber : secondActivationBlockNumber;

        ILOVELYPairToken(pair).initializeValidated(tokenC, validationAmount, fee, activationBlockNumber);
        getPair[token0][token1] = pair;

        // Populate mapping in the reverse direction
        getPair[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }
}
