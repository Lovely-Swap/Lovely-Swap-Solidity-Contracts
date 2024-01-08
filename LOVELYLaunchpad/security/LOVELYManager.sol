// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity =0.8.15;

import "../interfaces/ISharedData.sol";

abstract contract LOVELYManager is ISharedData {

    //minimun duration of singe ILO in seconds = 30 minutes
    uint constant MIN_ILO_DURATION = 1800;

    //maximum duration of singe ILO in seconds = 7 days
    uint constant MAX_ILO_DURATION = 604800;

    modifier onlyOwner(address sender, address owner) {
        require(sender == owner, "LOVELY ILO: Message sender is not sale owner");
        _;
    }

    modifier onlyOwnerOrManager(address sender, address owner, mapping(address => bool) storage managers) {
        bool isManager = managers[sender];
        bool isOwner = false;

        if (sender == owner) { isOwner = true; }

        require(isManager == true || isOwner == true, "LOVELY ILO: Message sender is not sale owner or manager");
        _;
    }

    modifier isManagerAlreadyExist(address newManager, mapping (address => bool) storage managers) {
        require(managers[newManager] == false, "LOVELY ILO: Manager has already been added");
        _;
    }

    modifier isManagerExist(address _manager, mapping (address => bool) storage managers) {
        require(managers[_manager] == true, "LOVELY ILO: Manager not exist");
        _;
    }

    modifier blockDuration(uint256 _blockFrom, uint256 _blockTo, uint256 oneBlockCreationTime) {
        require(_blockFrom <= _blockTo, "LOVELY ILO: startDepositTime should be lower then endDepositTime");

        uint256 minTime = MIN_ILO_DURATION / oneBlockCreationTime;
        uint256 maxTime = MAX_ILO_DURATION / oneBlockCreationTime;
        uint256 duration = _blockTo - _blockFrom;
        
        // Check that new ILO duration is within the minimum and maximum allowed limits
        require(
            duration >= minTime,
            "LOVELY ILO: Minimum ILO duration should be more than 30 minutes"
        );
        require(
            duration <= maxTime,
            "LOVELY ILO: Maximum ILO duration should be less or equal to 7 days"
        );
        _;
    }
}