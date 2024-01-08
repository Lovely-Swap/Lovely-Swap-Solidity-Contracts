// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.15;

import "./Lovelyswap/v2-core-patched/LovelyswapV2Pair.sol";
import "./interfaces/ILOVELYTokenList.sol";

/**
    @title The token listing controller.

    Keeps the list of tokens available in the ecosystem and their additional metadata.
 */
contract LOVELYTokenList is ILOVELYTokenList {

    /**
        The token memory slot.
     */
    struct Token {

        // Amount, which must be paid to make the token valid
        uint256 validationAmount;

        // A token, in which this amount should be paid
        address validationToken;

        // A block number, after which the token becomes active
        uint activationBlockNumber;
    }

    /**
        The list of tokens registered.
     */
    address[] public addresses;

    /**
        A manager, capable to change the validation amount recipient.
     */
    address public feeToSetter;

    /**
        The default amount to be paid while listing the token.
        This amount is paid when the token is listed by a contract which is not the DEX owner.
     */
    uint private defaultValidationAmount;

    /**
        The default validation token for listing the token.
     */
    address public defaultValidationToken;

    /**
        A reference to the DEX owner.
     */
    address private owner;

    // Additional metadata for registered tokens.
    mapping(address => Token) private slots;

    /**
        The validation amount recipient.
     */
    address private feeTo;

    /**
        Triggered, when the default validation amount is set.
     */
    event SetDefaultValidationAmount(uint _value);

    /**
        Triggered, when the default validation amount is set.
     */
    event SetDefaultValidationToken(address _value);

    /**
        Triggered, when a fee recipient is set.

        @param _feeTo The given activation amount recipient address.
     */
    event SetFeeTo(address _feeTo);

    /**
        Triggered, when the new fee setter is set.

        @param _feeToSetter The new address of the one who can change the activation amount.
     */
    event SetFeeToSetter(address _feeToSetter);

    /**
        Triggered, when a new token is listed.

        @param _token The token to be added.
        @param _validationToken The token, in which the validation amount is paid.
        @param _validationAmount The validation amount override only available to the DEX owner.
        @param _activationBlockNumber The block number, after which the registered token becomes active / trading is started.
     */
    event Add(
        address _token,
        address _validationToken,
        uint _validationAmount,
        uint _activationBlockNumber
    );

    /**
        Triggered, when the validation token for the given token is set.

        @param _token The given token.
        @param theValidationToken The new validation token to be set.
     */
    event SetValidationTokenAt(address _token, address theValidationToken);

    /**
        Triggered, when the validation amount for the given token is set.

        @param _token The given token.
        @param theValidationAmount The validation amount to be set.
     */
    event SetValidationAmountAt(address _token, uint256 theValidationAmount);

    /**
        Triggered, when the activation block number for the given token is set.

        @param _token The given token.
        @param theActivationBlockNumber The activation block number to be set.
     */
    event SetActivationBlockNumberAt(address _token, uint theActivationBlockNumber);

    /**
        Creates the token listing registry instance.

        @param _owner The DEX owner address.
     */
    constructor(address _owner) {

        require(address(0) != _owner, "LOVELY DEX: ZERO_ADDRESS");

        owner = _owner;
        feeTo = _owner;
        feeToSetter = _owner;
    }

    /**
        Returns the default validation amount value.
     */
    function getDefaultValidationAmount() external view returns (uint) {
        return defaultValidationAmount;
    }

    /**
        Sets the default validation amount value.

        @param _value The given validation amount value to be set.

        Can only be set by the DEX owner.
     */
    function setDefaultValidationAmount(uint _value) external {

        require(owner == msg.sender, 'LOVELY DEX: FORBIDDEN');

        defaultValidationAmount = _value;

        emit SetDefaultValidationAmount(_value);
    }

    /**
        Returns the default validation token address.
     */
    function getDefaultValidationToken() external view returns (address) {
        return defaultValidationToken;
    }

    /**
        Sets the default validation token address.

        @param _value The given validation amount value to be set.

        Can only be set by the DEX owner.
     */
    function setDefaultValidationToken(address _value) external {

        require(owner == msg.sender, 'LOVELY DEX: FORBIDDEN');

        defaultValidationToken = _value;

        emit SetDefaultValidationToken(_value);
    }

    /**
        Adds the token into the listing registry.
        To add the token, it is necessary to pay the given validation amount.
        The validation amount it either the default one when the token is added by the anonymous account.
        Or the validation amount can be defined / overridden by the DEX owner while adding the token.
        The token can be registered and activated immediately or activation can be delayed until the given block.

        @param _token The token to be added.
        @param _validationToken The token, in which the validation amount is paid.
        @param _validationAmount The validation amount override only available to the DEX owner.
        @param _activationBlockNumber The block number, after which the registered token becomes active / trading is started.
     */
    function add(
        address _token,
        address _validationToken,
        uint _validationAmount,
        uint _activationBlockNumber
    ) external {

        // Cannot add the token twice
        require(slots[_token].validationToken == address(0x0), 'LOVELY DEX: EXISTS');

        // Non-DEX-owners cannot re-define validation amount
        require(msg.sender == owner || _validationAmount == defaultValidationAmount, "LOVELY DEX: TOKEN_LIST_VALIDATION_AMOUNT");

        if (msg.sender != owner) {
            require(_validationToken == defaultValidationToken, 'LOVELY DEX: TOKEN_LIST_VALIDATION_TOKEN');
        }

        // Validate the token being added
        IERC20(_validationToken).transferFrom(msg.sender, feeTo, _validationAmount);

        // Save requirements for token validation
        slots[_token].validationToken = _validationToken;
        slots[_token].validationAmount = _validationAmount;
        slots[_token].activationBlockNumber = _activationBlockNumber;

        // Save to an address index.
        // This cannot happen twice.
        // So, there are no search checks.
        addresses.push(_token);

        emit Add(_token, _validationToken, _validationAmount, _activationBlockNumber);
    }

    /**
        Returns the token address corresponding to the given index.

        @param i The given index.
     */
    function at(uint i) external view returns (address) {

        require(i < addresses.length, "LOVELY DEX: NOT_EXISTS");

        return addresses[i];
    }

    /**
        Returns the length of the token registry.
     */
    function length() external view returns (uint256) {
        return addresses.length;
    }

    /**
        Returns the validation amount corresponding to the given token index.

        @param i The given index.
     */
    function validationAmountAt(uint i) external view returns (uint256) {

        require(i < addresses.length, "LOVELY DEX: NOT_EXISTS");

        return slots[addresses[i]].validationAmount;
    }

    /**
        Returns the token address in which the validation amount is paid for the given token index.

        @param i The given index.
     */
    function validationTokenAt(uint i) external view returns (address) {

        require(i < addresses.length, "LOVELY DEX: NOT_EXISTS");

        return slots[addresses[i]].validationToken;
    }

    /**
        Returns the activation block number for the given token.

        @param token The given token address.
     */
    function activationBlockNumberFor(address token) external view returns (uint) {
        return slots[token].activationBlockNumber;
    }

    /**
        Sets the activation amount recipient address.

        @param _feeTo The given activation amount recipient address.
     */
    function setFeeTo(address _feeTo) external {

        require(msg.sender == feeToSetter, 'LOVELY DEX: FORBIDDEN');
        require(address(0) != _feeTo, "LOVELY DEX: ZERO_ADDRESS");

        feeTo = _feeTo;

        emit SetFeeTo(_feeTo);
    }

    /**
        Sets the address, which can change the activation amount recipient address.

        @param _feeToSetter The new address of the one who can change the activation amount.
     */
    function setFeeToSetter(address _feeToSetter) external {

        require(msg.sender == feeToSetter, 'LOVELY DEX: FORBIDDEN');
        require(address(0) != _feeToSetter, "LOVELY DEX: ZERO_ADDRESS");

        feeToSetter = _feeToSetter;

        emit SetFeeToSetter(_feeToSetter);
    }

    /**
        Returns whether the given token is activated / validated.

        @param _token The given token.
     */
    function validated(address _token) external view override returns (bool) {
        return slots[_token].validationToken != address(0x0);
    }
}
