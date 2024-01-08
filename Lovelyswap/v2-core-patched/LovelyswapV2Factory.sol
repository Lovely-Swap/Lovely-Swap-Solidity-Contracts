// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import '../interfaces/ILovelyswapV2Factory.sol';
import './LovelyswapV2Pair.sol';

abstract contract LovelyswapV2Factory is ILovelyswapV2Factory {
    address public override feeTo;
    address public override feeToSetter;

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external override view returns (uint) {
        return allPairs.length;
    }

    function setFeeTo(address _feeTo) override external {
        require(msg.sender == feeToSetter, 'LOVELYV4: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) override external {
        require(msg.sender == feeToSetter, 'LOVELYV4: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
