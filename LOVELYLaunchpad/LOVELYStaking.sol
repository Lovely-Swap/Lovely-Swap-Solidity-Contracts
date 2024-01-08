// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract LOVELYStakeManager {
    modifier onlyManager(mapping(address => bool) storage managerList) {
        require(managerList[msg.sender], "LOVELY Staking: User is not a manager");
        _;
    }
}

//if unstake update reward;

contract LOVELYStaking is LOVELYStakeManager {
    using SafeERC20 for IERC20;

    // LOVELY Token address
    IERC20 public lovelyInu;

    //managers array
    mapping (address => bool) managers;

    //one block creation time in seconds
    uint internal immutable oneBlockCreationTime;

    //stake reward amount
    uint256 public rewardAmount;

    //one day in seconds
    uint internal constant DAY = 86400;

    struct User {
        //deposited amount
        uint256 deposited;

        //last update in blicks
        uint256 lastUpdateTime;

        //earned amount of lovely
        uint256 earned;
    }

    //all users
    mapping (address => User) public users;

    //total stakes
    uint256 public totalStakes;

    //reward rate
    uint256 public rewardRate = 2;

    //last stake update
    uint256 public lastUpdate;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(address _lovelyInuAddress, uint _oneBlockCreationTime) {
        lovelyInu = IERC20(_lovelyInuAddress);
        lastUpdate = block.number;
        managers[msg.sender] = true;
        oneBlockCreationTime = _oneBlockCreationTime;
    }

    /**
     * Fransfers amount of tokens that user want to stake
     * 
     * @param amount amount of tokens to stake
     */
    function stake(uint256 amount) external payable {
        require(amount > 0, "LOVELY Staking: Amount must be greater than 0");
        require(lovelyInu.balanceOf(msg.sender) >= amount, "LOVELY Staking: Insufficient balance");

        lovelyInu.transferFrom(msg.sender, address(this), amount);

        users[msg.sender].deposited += amount;
        totalStakes += amount;

        _updateReward(msg.sender);

        emit Staked(msg.sender, amount);
    }

    /**
     * Transfers amount of tokens that user want to unstake
     * 
     * @param amount amount of tokens to anstake
     */
    function unstake(uint256 amount) external payable {
        require(amount > 0, "LOVELY Staking: Amount must be greater than 0");
        require(users[msg.sender].deposited >= amount, "LOVELY Staking: Insufficient stake");

        _updateReward(msg.sender);

        users[msg.sender].deposited -= amount;
        totalStakes -= amount;

        assert(lovelyInu.transfer(msg.sender, amount));
        emit Unstaked(msg.sender, amount);
    }

    /**
     * Transfers _amount of tokens as reward
     * 
     * @param _amount amount of tokens that users can earn
     */
    function addRewardAmount(uint256 _amount) external onlyManager(managers) {
        require(_amount > 0, "LOVELY Staking: Amount must be greater than 0");
        require(lovelyInu.balanceOf(msg.sender) >= _amount, "LOVELY Staking: Insufficient balance");

        rewardAmount += _amount;
        lovelyInu.transferFrom(msg.sender, address(this), _amount);
    }

    /**
     * View saking deposited amount
     */
    function getUserStakeAmount() public view returns(uint256) {
        return users[msg.sender].deposited;
    }

    /**
     * Add new manager in contract
     * 
     * @param _user new manager address
     */
    function addManager(address _user) public onlyManager(managers) {
        managers[_user] = true;
    }

    /**
     * Removes axisting manager from list
     * 
     * @param _user address of existing manager
     */
    function removeManager(address _user) public onlyManager(managers) {
        require(managers[_user], "LOVELY Staking: User not exist");
        delete managers[_user];
    }

    /**
     * Trunsfers earned amount
     */
    function getReward() public payable {
        _updateReward(msg.sender);

        uint256 reward = users[msg.sender].earned;
        if (rewardAmount >= reward) {
            lovelyInu.transfer(msg.sender, reward);
            users[msg.sender].earned = 0;
            rewardAmount -= reward;
        } else {
            lovelyInu.transfer(msg.sender, rewardAmount);
            users[msg.sender].earned = 0;
            rewardAmount = 0;
        }

        emit RewardPaid(msg.sender, reward);
    }

    /**
     * Returns updated reward
     * 
     * @param account message sender address
     */
    function _updateReward(address account) internal {
        rewardRate = rewardAmount / totalStakes / 365;
        lastUpdate = block.number;

        users[account].earned += _earned(account);
        users[account].lastUpdateTime = block.number;
    }

    /**
     * Returns earned amount
     * 
     * @param account message sender address
     */
    function _earned(address account) internal view returns (uint256) {
        uint256 day = DAY / oneBlockCreationTime;
        uint256 timeSinceLastUpdate = (block.number - users[account].lastUpdateTime) / day;

        return ((users[account].deposited * rewardRate) / 100) * timeSinceLastUpdate;
    }
}