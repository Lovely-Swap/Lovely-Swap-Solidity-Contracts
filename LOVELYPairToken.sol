// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.15;

import "./Lovelyswap/v2-core-patched/LovelyswapV2Pair.sol";
import "./interfaces/ILOVELYPairToken.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LOVELYPairToken is ILOVELYPairToken, LovelyswapV2Pair {

    /**
        Liquidity pool maximum fee value.

        It is not allowed to set more than 1.0% swapping fees.
     */
    uint256 private constant MAXIMUM_FEE = 10;

    /**
        The address of a token in which the validation amount is paid.
     */
    address private _validationToken;

    /**
        Token amount to be paid for the validation.
     */
    uint private _validationTokenAmount;

    /**
        The block number, after which the token becomes trade-able.
     */
    uint private _activationBlockNumber;

    /**
        Triggered, when a fee is set for this liquidity pool.

        @param _fee The new fee.
     */
    event SetFee(uint _fee);

    /**
       Triggered, when the liquidity pool is validated.
     */
    event Validate();

    /**
        Triggered, when the validated pair is initialized.

        @param _token The validation token address.
        @param _amount Validation amount to be paid to validate the pool.
        @param _fee The fee, applicable in this pool.
        @param __activationBlockNumber The block number, after which the pool becomes trade-able.
     */
    event InitializeValidatedPair(address _token, uint _amount, uint _fee, uint __activationBlockNumber);

    /**
        Apply SafeERC20 to all IERC20 tokens in this contract.
     */
    using SafeERC20 for IERC20;

    /**
        Initializes a validated pair.

        @param _token The validation token address.
        @param _amount Validation amount to be paid to validate the pool.
        @param _fee The fee, applicable in this pool.
        @param __activationBlockNumber The block number, after which the pool becomes trade-able.
     */
    function initializeValidated(address _token, uint _amount, uint _fee, uint __activationBlockNumber) external {

        require(msg.sender == factory, 'LOVELY DEX: FORBIDDEN');
        require(_fee <= MAXIMUM_FEE, "LOVELY DEX: FEE_LIMIT");
        require(address(0) != _token, "LOVELY DEX: ZERO_ADDRESS");

        _validationToken = _token;
        _validationTokenAmount = _amount;
        fee = _fee;
        _activationBlockNumber = __activationBlockNumber;

        emit InitializeValidatedPair(_token, _amount, _fee, __activationBlockNumber);
    }

    /**
        Returns data about validation constraints for this pool.
     */
    function getValidationConstraint() external view returns (address validationToken, uint validationTokenAmount) {
        return (_validationToken, _validationTokenAmount);
    }

    /**
        Sets the fee for this liquidity pool.

        @param _fee The new fee.
     */
    function setFee(uint _fee) external {

        require(msg.sender == ILovelyswapV2Factory(factory).feeToSetter(), "LOVELY DEX: FORBIDDEN");
        require(_fee <= MAXIMUM_FEE, "LOVELY DEX: FEE_LIMIT");

        fee = _fee;

        emit SetFee(_fee);
    }

    /**
        Takes the validation amount in the specified validation token and marks the pool as valid.
     */
    function validate() external {

        address feeTo = ILovelyswapV2Factory(factory).feeTo();
        require(feeTo != address(0), "LOVELY DEX: NON_FEE_PAIR");
        IERC20(_validationToken).transferFrom(msg.sender, feeTo, _validationTokenAmount);
        _validationTokenAmount = 0;

        emit Validate();
    }

    /**
        Returns pool reserves available.
        Blocks any swap operations for non-validated pools.

        Getting reserves is the first step of adding liquidity.
        So, assuming that blocking getting reserves for non-validated pairs will block creating liquidity.
     */
    function getReserves() public view override(ILovelyswapV2Pair, LovelyswapV2Pair) returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        require(0 == _validationTokenAmount, "LOVELY DEX: NON_VALIDATED_PAIR");
        return super.getReserves();
    }

    /**
        Returns, how many blocks need to be mined before this pool becomeas active.
     */
    function getRemainingActivationBlocks() public view override(ILOVELYPairToken, LovelyswapV2Pair) returns (uint) {
        if (_activationBlockNumber <= block.number) {
            return 0;
        }
        return _activationBlockNumber - block.number;
    }

    /**
        Returns the fee for this pool.
     */
    function getFee() public view override(ILOVELYPairToken, LovelyswapV2Pair) returns (uint) {
        return fee;
    }
}
