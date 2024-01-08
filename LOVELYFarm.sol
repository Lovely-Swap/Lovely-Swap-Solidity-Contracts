// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
    A farming pool contract.
    Creates time-limited farming pools, which can accept deposits and
    provide rewards to deposit owners.

    The farming pool may accept fees while withdrawing.
    It is recommended to use zero fees.
    The fee cannot be more that 4%.
 */
contract LOVELYFarm is Ownable, ReentrancyGuard {

    /**
        Stores data about the farm user.
     */
    struct User {
        uint256 amount;
        uint256 rewardDebt;
    }

    /**
        Stores data about the farming pool.
     */
    struct Pool {

        // The farming pool owner.
        address owner;

        // The address to receive any collected commissions.
        address refundAddress;

        // All pool users.
        mapping(address => User) users;

        // Pool withdrawal fee.
        uint fee;

        // Total collected fee amount.
        uint256 feeAmount;

        // Pool liquidity token, which is farmed.
        IERC20 liquidityToken;

        // Pool reward token, in which the rewards are paid.
        IERC20 rewardToken;

        // A multiplier to increase pool rewards.
        uint256 rewardMultiplier;

        // Pool reward per liquidity share.
        // Re-calculated in the "updatePool" method.
        uint256 rewardPerShare;

        // Overall pool reward per block.
        uint256 rewardPerBlock;

        // Overall pool reward token amount.
        uint256 rewardTokenAmount;

        // Block time when the reward was re-calculated the previous time.
        uint256 rewardLastBlock;

        // Total rewarded in the pool.
        uint256 rewardTotal;

        // Block time, when the farming starts.
        uint256 rewardStartBlock;

        // Block time, when the farming ends.
        uint256 rewardEndBlock;
    }

    /**
        Amount of pools created.
     */
    uint256 public poolCount;

    /**
        The fee calculations denominator.

        The nominator during fee calculations goes in the following format:
        - *XXY;
        - where *XX is the integer part of the fee percentage;
        - and Y is the 1-decimal fractional part of the percentage.

        Therefore, the *XXY integer divided by 1000 equals *XX.Y% percentage multiplier.
     */
    uint256 private constant FEE_DENOMINATOR = 1000;

    /**
        A decimal part conversion quantifier to keep decimal numbers in the more compact format.
     */
    uint256 private constant E12_QUANTIFIER = 1e12;

    /**
        An initial value for the reward multiplier meaning that a single scale of the reward is being paid-off.
     */
    uint256 private constant SINGLE_REWARD_MULTIPLIER = 1;

    /**
        Farming pool state meaning that the pool was created but not yet started.
     */
    uint256 private constant POOL_STATE_CREATED = 0;

    /**
        Farming pool state meaning that the pool is actively farming.
     */
    uint256 private constant POOL_STATE_ACTIVE = 1;

    /**
        Farming pool state meaning that the farming has ended.
     */
    uint256 private constant POOL_STATE_ENDED = 2;

    /**
        Farming pool maximum fee value.

        It is not allowed to set more than 4.0% farming fee.
     */
    uint256 private constant MAXIMUM_FEE = 40;

    /**
        All pools, corresponding to the pool identifier.
     */
    mapping(uint256 => Pool) private pools;

    /**
        Event, triggered when the deposit occurs.
     */
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);

    /**
        Event, triggered when the withdraw occurs.
     */
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    /**
        Event, triggered when the emergency withdraw occurs.
     */
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    /**
        Triggered, when a liquidity token for a pool is set.

        @param _poolIdentifier The given pool identifier.
        @param _liquidityToken The liquidity token to be set.
     */
    event Add(uint256 _poolIdentifier, IERC20 _liquidityToken);

    /**
        Triggered, when a fee is set for a given pool.

        @param _poolIdentifier The given pool identifier.
        @param _fee The new fee.
     */
    event SetFee(uint256 _poolIdentifier, uint _fee);

    /**
        Triggered, when a new farming pool is created.

        @param _rewardToken A token, in which rewards are paid.
        @param _owner The farming pool owner.
        @param _refundAddress The address capable of receiving and additional funds, not belonging to users.
        @param _rewardTokenAmount Total amount to be rewarded in this pool.
        @param _startBlock Farming start block.
        @param _endBlock Farming end block.
     */
    event CreatePool(
        IERC20 _rewardToken,
        address _owner,
        address _refundAddress,
        uint256 _rewardTokenAmount,
        uint256 _startBlock,
        uint256 _endBlock
    );

    /**
        Triggered, when a pool reward multiplier is updated.

        @param _poolIdentifier The given pool identifier.
        @param _multiplier The multiplier value to be set.
     */
    event UpdateRewardMultiplier(uint256 _poolIdentifier, uint256 _multiplier);

    /**
        Triggered, when a pool refund address is updated.

        @param _poolIdentifier The given pool identifier.
        @param _refundAddress The new refund address.
     */
    event UpdateRefundAddress(uint256 _poolIdentifier, address _refundAddress);

    /**
        Triggered, when a farming pool owner is updated.

        @param _poolIdentifier The given pool identifier.
        @param _owner The new pool owner.
     */
    event UpdatePoolOwner(uint256 _poolIdentifier, address _owner);

    /**
        Triggered, when the farm's collected fees are withdrawn by the DEX owner.

        @param _poolIdentifier The given pool identifier.
     */
    event WithdrawFees(uint256 _poolIdentifier);

    /**
        Apply SafeERC20 to all IERC20 tokens in this contract.
     */
    using SafeERC20 for IERC20;

    /**
        A modifier to mark methods, invokable only by the DEX or pool owner.

        @param _poolIdentifier The given pool identifier.
     */
    modifier onlyOwnerOrPoolOwner(uint256 _poolIdentifier) {
        require(
            pools[_poolIdentifier].owner == msg.sender || owner() == msg.sender,
            "LOVELY DEX: FORBIDDEN"
        );
        _;
    }

    /**
        Returns the liquidity token address of a given farming pool.

        @param _poolIdentifier The given pool identifier.

        @return The corresponding liquidity token address.
     */
    function at(uint256 _poolIdentifier) external view returns (address) {

        require(_poolIdentifier < poolCount, "LOVELY DEX: NOT_EXISTS");

        return address(pools[_poolIdentifier].liquidityToken);
    }

    /**
        Sets the new fee for a given pool.
        The fee cannot be more than the MAXIMUM_FEE value.

        @param _poolIdentifier The given pool identifier.
        @param _fee The new fee.
     */
    function setFee(uint256 _poolIdentifier, uint _fee) external onlyOwner {

        require(_fee <= MAXIMUM_FEE, "LOVELY FARM: FEE_LIMIT");

        pools[_poolIdentifier].fee = _fee;

        emit SetFee(_poolIdentifier, _fee);
    }

    /**
        Returns the fee of a given pool.

        @param _poolIdentifier The given pool identifier.

        @return The fee of a given pool.
     */
    function getFee(uint256 _poolIdentifier) external view returns (uint) {
        return pools[_poolIdentifier].fee;
    }

    /**
        Creates a new farming pool.

        @param theRewardToken A token, in which rewards are paid.
        @param theLiquidityToken The liquidity token to be set.
        @param theOwner The farming pool owner.
        @param theRefundAddress The address capable of receiving and additional funds, not belonging to users.
        @param theRewardTokenAmount Total amount to be rewarded in this pool.
        @param theStartBlock Farming start block.
        @param theEndBlock Farming end block.

        @return The newly created farming pool identifier.
     */
    function createPool(
        IERC20 theRewardToken,
        IERC20 theLiquidityToken,
        address theOwner,
        address theRefundAddress,
        uint256 theRewardTokenAmount,
        uint256 theStartBlock,
        uint256 theEndBlock
    ) external onlyOwner returns (uint256) {

        require(
            theEndBlock > theStartBlock,
            "LOVELY FARM: END_LESS_START_BLOCK"
        );
        require(
            theStartBlock >= block.number,
            "LOVELY FARM: START_LESS_CURRENT_BLOCK"
        );
        require(
            theRewardTokenAmount > 0,
            "LOVELY FARM: ZERO_REWARD"
        );
        require(
            theRefundAddress != address(0),
            "LOVELY FARM: NO_REFUND_ADDRESS"
        );
        require(
            theOwner != address(0),
            "LOVELY FARM: NO_OWNER_ADDRESS"
        );

        // The reward token can
        // neither be one of the liquidity tokens of other pools,
        // nor the liquidity token of the newly created pool.
        bool found = false;
        for (uint256 i = 0; i < poolCount; i++) {
            if (theRewardToken == pools[i].liquidityToken) {
                found = true;
                break;
            }
        }
        require(
            !found && theRewardToken != theLiquidityToken,
            "LOVELY FARM: REWARD_LIQUIDITY_SAME"
        );

        uint256 id = poolCount++;
        Pool storage pool = pools[id];

        // By-default, a single reward is given
        pool.rewardMultiplier = SINGLE_REWARD_MULTIPLIER;
        pool.rewardTokenAmount = theRewardTokenAmount;
        pool.rewardStartBlock = theStartBlock;
        pool.rewardLastBlock = theStartBlock;
        pool.rewardEndBlock = theEndBlock;
        pool.rewardPerBlock = theRewardTokenAmount / (theEndBlock - theStartBlock);
        pool.rewardPerShare = 0;
        pool.rewardToken = theRewardToken;
        pool.refundAddress = theRefundAddress;
        pool.owner = theOwner;
        pool.liquidityToken = theLiquidityToken;

        emit CreatePool(theRewardToken, theOwner, theRefundAddress, theRewardTokenAmount, theStartBlock, theEndBlock);
        emit Add(id, theLiquidityToken);

        return id;
    }

    /**
        Returns the given pool time length in block time.

        @param _poolIdentifier The given pool identifier.

        @return The given pool time length in block time.
     */
    function blockPeriod(uint256 _poolIdentifier) external view returns (uint256) {
        return pools[_poolIdentifier].rewardEndBlock - pools[_poolIdentifier].rewardStartBlock;
    }

    /**
        Returns the given pool remaining time to the farming start.

        @param _poolIdentifier The given pool identifier.

        @return The given pool remaining time to the farming start.
     */
    function blockPeriodToStart(uint256 _poolIdentifier) external view returns (uint256) {
        return pools[_poolIdentifier].rewardStartBlock - block.number;
    }

    /**
        Returns the given pool liquidity token balance of a user.

        @param _poolIdentifier The given pool identifier.

        @return The given pool liquidity balance of a user.
     */
    function liquidityPoolBalanceOfUser(uint256 _poolIdentifier) external view returns (uint256) {
        return pools[_poolIdentifier].users[msg.sender].amount;
    }

    /**
        Returns the given farming pool's status.

        Can be one of the following:
        - POOL_STATE_CREATED (0), pool has not been started yet;
        - POOL_STATE_ACTIVE (1), pool farming in progress;
        - POOL_STATE_ENDED (2), pool farming ended.

        @param _poolIdentifier The given pool identifier.
        @return Requested pool status.
     */
    function getStatus(uint256 _poolIdentifier) external view returns (uint256) {
        if (pools[_poolIdentifier].rewardStartBlock > block.number) {
            return POOL_STATE_CREATED;
        } else if (
            pools[_poolIdentifier].rewardStartBlock <= block.number &&
            pools[_poolIdentifier].rewardTotal <
            pools[_poolIdentifier].rewardTokenAmount
        ) {
            return POOL_STATE_ACTIVE;
        } else {
            return POOL_STATE_ENDED;
        }
    }

    /**
        Sets the given pool reward multiplier.

        As an integer number, _multiplier can be set to zero.
        Therefore, rewards can be disabled after
        re-calculating the current time interval's reward.

        @param _poolIdentifier The given pool identifier.
        @param _multiplier The multiplier value to be set.
     */
    function updateRewardMultiplier(uint256 _poolIdentifier, uint256 _multiplier)
    external
    onlyOwner
    {
        updatePool(_poolIdentifier);

        pools[_poolIdentifier].rewardMultiplier = _multiplier;

        emit UpdateRewardMultiplier(_poolIdentifier, _multiplier);
    }

    /**
        Changes the given pool refund address.

        @param _poolIdentifier The given pool identifier.
        @param _refundAddress The new refund address.
     */
    function updateRefundAddress(uint256 _poolIdentifier, address _refundAddress)
    external
    onlyOwnerOrPoolOwner(_poolIdentifier)
    {
        pools[_poolIdentifier].refundAddress = _refundAddress;

        emit UpdateRefundAddress(_poolIdentifier, _refundAddress);
    }

    /**
        Changes the given pool owner.

        @param thePoolIdentifier The given pool identifier.
        @param theOwner The new pool owner.
     */
    function updatePoolOwner(uint256 thePoolIdentifier, address theOwner)
    external
    onlyOwnerOrPoolOwner(thePoolIdentifier)
    {
        pools[thePoolIdentifier].owner = theOwner;

        emit UpdatePoolOwner(thePoolIdentifier, theOwner);
    }

    /**
        Returns amount of pending tokens for the given user.

        @param _poolIdentifier The given pool identifier.
        @param _user The given user address.

        @return Requested token amount.
     */
    function pendingToken(uint256 _poolIdentifier, address _user)
    external
    view
    returns (uint256)
    {
        Pool storage pool = pools[_poolIdentifier];
        User storage user = pools[_poolIdentifier].users[_user];
        uint256 rewardPerShare = pool.rewardPerShare;
        uint256 lpSupply = pool.liquidityToken.balanceOf(address(this));

        // The reward range span end in block time
        uint256 blockNumber = block.number;
        if (block.number > pools[_poolIdentifier].rewardEndBlock) {
            blockNumber = pools[_poolIdentifier].rewardEndBlock;
        }

        if (blockNumber > pool.rewardLastBlock && lpSupply != 0) {
            uint256 multiplier = getPeriodWeight(
                _poolIdentifier,
                pool.rewardLastBlock,
                blockNumber
            );
            uint256 tpb = pools[_poolIdentifier].rewardPerBlock;
            uint256 tokenReward = multiplier * tpb;
            rewardPerShare = rewardPerShare + tokenReward * E12_QUANTIFIER / lpSupply;
        }

        return user.amount * rewardPerShare / E12_QUANTIFIER - user.rewardDebt;
    }

    /**
        Deposits the given amount into the given pool.

        @param _poolIdentifier The given pool identifier.
        @param _amount The amount to be deposited.
     */
    function deposit(uint256 _poolIdentifier, uint256 _amount) external nonReentrant {

        Pool storage pool = pools[_poolIdentifier];
        User storage user = pools[_poolIdentifier].users[msg.sender];

        updatePool(_poolIdentifier);

        if (user.amount > 0) {
            uint256 pending = user.amount * pool.rewardPerShare / E12_QUANTIFIER - user.rewardDebt;
            if (pending > 0) {
                safeTokenTransfer(_poolIdentifier, msg.sender, pending);
            }
        }

        if (_amount > 0) {
            pool.liquidityToken.transferFrom(msg.sender, address(this), _amount);
            user.amount = user.amount + _amount;
        }

        user.rewardDebt = user.amount * pool.rewardPerShare / E12_QUANTIFIER;

        emit Deposit(msg.sender, _poolIdentifier, _amount);
    }

    /**
        Withdraws the given amount from the given pool.
        While, withdrawing, the reward is also withdrawn.
        To withdraw only the reward, invoke withdraw(..., 0).

        @param _poolIdentifier The given pool identifier.
        @param _amount The amount to be withdrawn.
     */
    function withdraw(uint256 _poolIdentifier, uint256 _amount)
    external
    nonReentrant
    {
        Pool storage pool = pools[_poolIdentifier];
        User storage user = pool.users[msg.sender];

        updatePool(_poolIdentifier);

        require(user.amount >= _amount, "LOVELY FARM: AMOUNT");

        uint256 pending = user.amount * pool.rewardPerShare / E12_QUANTIFIER - user.rewardDebt;
        if (pending > 0) {
            safeTokenTransfer(_poolIdentifier, msg.sender, pending);
        }

        if (_amount > 0) {
            uint256 fee = _amount * pool.fee / FEE_DENOMINATOR;
            uint256 transferableAmount = _amount - fee;
            user.amount = user.amount - _amount;
            pool.liquidityToken.transfer(msg.sender, transferableAmount);
            pool.feeAmount = pool.feeAmount + fee;
        }

        user.rewardDebt = user.amount * pool.rewardPerShare / E12_QUANTIFIER;

        emit Withdraw(msg.sender, _poolIdentifier, _amount);
    }

    /**
        Withdraws the deposit from the given pool, discarding the reward.

        @param _poolIdentifier The given pool identifier.
     */
    function withdrawEmergency(uint256 _poolIdentifier) external nonReentrant {
        Pool storage pool = pools[_poolIdentifier];
        User storage user = pool.users[msg.sender];
        uint256 fee = user.amount * pool.fee / FEE_DENOMINATOR;
        uint256 transferableAmount = user.amount - fee;
        pool.liquidityToken.transfer(msg.sender, transferableAmount);
        pool.feeAmount = pool.feeAmount + fee;
        emit EmergencyWithdraw(msg.sender, _poolIdentifier, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    /**
        Withdraws any collected fees to the refund address.

        @param _poolIdentifier The given pool identifier.
     */
    function withdrawFees(uint256 _poolIdentifier)
    external
    onlyOwner
    nonReentrant
    {
        Pool storage pool = pools[_poolIdentifier];
        uint256 amount = pool.feeAmount;
        require(amount > 0, "LOVELY FARM: NO_FEES");
        pool.feeAmount = 0;
        pool.liquidityToken.transfer(pool.refundAddress, amount);

        emit WithdrawFees(_poolIdentifier);
    }

    /**
        Returns the remaining reward amount of a given pool.

        @param _poolIdentifier The given pool identifier.

        @return The remaining reward amount of a pool.
     */
    function left(uint256 _poolIdentifier) public view returns (uint256) {
        return pools[_poolIdentifier].rewardTokenAmount - pools[_poolIdentifier].rewardTotal;
    }

    /**
        Returns the given pool liquidity token balance of the whole pool.

        @param _poolIdentifier The given pool identifier.

        @return The given pool total liquidity.
     */
    function liquidityTokenBalanceOfPool(uint256 _poolIdentifier) public view returns (uint256) {
        return pools[_poolIdentifier].liquidityToken.balanceOf(address(this));
    }

    /**
         Returns the given pool's reward per share

        @param _poolIdentifier The given pool identifier.

        @return Requested reward per share of a given pool.
     */
    function getRewardPerShare(uint256 _poolIdentifier) public view returns (uint256) {
        return pools[_poolIdentifier].rewardPerShare;
    }

    /**
        Returns the reward time span in the block time,
        considering the given pool reward multiplier.

        The span is calculated by the following formula:
        r(from, to) = (to - from) * multiplier.

        @param _poolIdentifier The pool identifier, for which to calculate.
        @param _from The range start block.
        @param _to The range end block.

        @return The requested reward coefficient.
     */
    function getPeriodWeight(
        uint256 _poolIdentifier,
        uint256 _from,
        uint256 _to
    ) public view returns (uint256) {
        return (_to - _from) * pools[_poolIdentifier].rewardMultiplier;
    }

    /**
        Updates the given pool' reward characteristics.

        @param _poolIdentifier The given pool.
     */
    function updatePool(uint256 _poolIdentifier) public {

        Pool storage pool = pools[_poolIdentifier];

        // The pool has already been updated
        if (block.number <= pool.rewardLastBlock) {
            return;
        }

        // Liquidity token supply
        uint256 liquiditySupply = pool.liquidityToken.balanceOf(address(this)) - pool.feeAmount;

        // No reward token supply
        if (0 == liquiditySupply) {
            pool.rewardLastBlock = block.number;
            return;
        }

        // Calculate the reward period weight
        // from the last reward time
        // till now
        // for the given pool
        // considering the pool reward multiplier.
        uint256 rewardForPeriod = getPeriodWeight(_poolIdentifier, pool.rewardLastBlock, Math.min(block.number, pool.rewardEndBlock));

        // Calculate the reward.
        uint256 reward = rewardForPeriod * pool.rewardPerBlock;

        // Calculate the new pool's reward per share.
        pool.rewardPerShare = pool.rewardPerShare + reward * E12_QUANTIFIER / liquiditySupply;

        // Update the pool's last reward block.
        pool.rewardLastBlock = Math.min(block.number, pool.rewardEndBlock);
    }

    /**
        Tries to transfer at least the available amount of the reward token.

        @param _poolIdentifier The given pool identifier.
        @param _to The reward token recipient address.
        @param _amount The reward token amount to be transferred.
     */
    function safeTokenTransfer(
        uint256 _poolIdentifier,
        address _to,
        uint256 _amount
    ) internal {
        uint256 tokenBal = pools[_poolIdentifier].rewardToken.balanceOf(address(this));
        if (_amount > tokenBal) {
            pools[_poolIdentifier].rewardToken.transfer(_to, tokenBal);
            pools[_poolIdentifier].rewardTotal += _amount;
        } else {
            pools[_poolIdentifier].rewardToken.transfer(_to, _amount);
            pools[_poolIdentifier].rewardTotal += _amount;
        }
    }
}
