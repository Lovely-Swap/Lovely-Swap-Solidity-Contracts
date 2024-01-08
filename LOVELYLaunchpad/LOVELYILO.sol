// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity =0.8.15;

import "./security/LOVELYManager.sol";
import "./LOVELYStaking.sol";
import "./LOVELYLaunchpad.sol";

import "../LOVELYFactory.sol";
import "../LOVELYRouter.sol";
import "../LOVELYTokenList.sol";

// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// /**
//  * @title ILO contract
//  * @dev ILO manager contract
//  * @author Eugene K (lineardev.ceo@gmail.com)
//  */
contract LOVELYILO is ISharedData, LOVELYManager, ReentrancyGuard  {
    using SafeERC20 for IERC20;

    //sale owner address
    address immutable owner;

    //one block creation time in seconds
    uint internal immutable oneBlockCreationTime;

    //one week in seconds
    uint internal constant WEEK = 604800;

    //30 minutes in seconds
    uint internal constant MINUTES = 1800;

    //LOVELY Staking contract address
    address public immutable LOVELYStakeContractAddress;

    //Launchpad address
    address public immutable _LOVELYLaunchpad;

    //LOVELY Token address
    address public immutable LOVELYTokenAddress;

    //USDT Token address
    address public immutable USDTTokenAddress;

    //Factory contract
    LOVELYFactory internal FactoryContract;

    //Router contract
    LOVELYRouter internal RouterContract;
    address internal immutable RouterContractAddress;

    //Staking contract
    LOVELYStaking internal StakingContract;

    //sale current cap
    uint256 public totalCap = 0;
    
    //user memory slot
    struct User {
        //useer deposited amount
        uint256 depositedAmount;

        //status of user claiming
        bool claimed;
    }

    // user memory slot
    struct UserBonus {
        //useer deposited amount
        uint256 depositedAmount;

        //time when user make deposit
        uint256 depositedTime;

        //claimed times
        uint claimings;
    }

    //ILO Participants memory slot
    mapping(address => User) users;

    //All ILO participant count
    uint256 usersLenght = 0;

    //Participants who want bonus
    mapping(address => UserBonus) userBonus;

    //sale params
    PublicSaleParams public saleInformation;
    PurchaseToken public purchaseToken;

    //array of sale managers
    mapping (address => bool) managers;

    event Deposit(address user, uint256 amount);

    event Claim(address user, uint256 depositedAmount);

    event AddManager(address manager);

    event RemoveManager(address manager);

    event DepositBonus(uint256 amount);

    event ClaimBonus(address user, uint256 amount);

    event UnstakeBonus(uint256 amount);

    event UpdateStartDepositTime(uint256 time);

    event UpdateEndDepositTime(uint256 time);

    event WithdrawTokenRewards(uint256 client);

    constructor(
        address _FactoryAddress,
        address payable _RouterAddress,
        PublicSaleParams memory _params,
        PurchaseToken memory _purchase,
        uint _oneBlockCreationTime,
        address _LOVELYStakeContractAddress,
        address _LOVELYLaunchpadContract,
        address LOVELYToken,
        address USDTToken
    ) {
        owner = _params.saleOwner;
        saleInformation = _params;
        purchaseToken = _purchase;
        oneBlockCreationTime = _oneBlockCreationTime;
        LOVELYStakeContractAddress = _LOVELYStakeContractAddress;
        StakingContract = LOVELYStaking(_LOVELYStakeContractAddress);
        LOVELYTokenAddress = LOVELYToken;
        USDTTokenAddress = USDTToken;
        FactoryContract = LOVELYFactory(_FactoryAddress);
        RouterContract = LOVELYRouter(_RouterAddress);
        RouterContractAddress = _RouterAddress;
        _LOVELYLaunchpad = _LOVELYLaunchpadContract;
    }

    /**
     * Deposits bonus in stake and save deposited time
     */
    function depositBonus() external payable {
        require(users[msg.sender].depositedAmount != 0, "LOVELY ILO: The user not deposited any amount of token");
        require(userBonus[msg.sender].depositedAmount == 0, "LOVELY ILO: The user has already deposited a bonus");
        require(saleInformation.extraQuantity != 0, "LOVELY ILO: Bonuses not able");
        uint inStake = getBonusAprovalAmount(msg.sender);

        IERC20 lovely = IERC20(LOVELYTokenAddress);
        uint256 userBalance = lovely.balanceOf(msg.sender);
        require(userBalance >= inStake, "LOVELY ILO: Insufisent amount");
        lovely.transferFrom(msg.sender, address(this), inStake);

        //getting farm contract and deposit bonus
        lovely.approve(LOVELYStakeContractAddress, inStake);
        StakingContract.stake(inStake);

        userBonus[msg.sender].depositedAmount = inStake;
        userBonus[msg.sender].depositedTime = block.number;
        userBonus[msg.sender].claimings = 0;

        emit DepositBonus(inStake);
    }

    /**
     * Allows to claim ILO extra quantity
     */
    function claimBonus() external payable {
        require(userBonus[msg.sender].depositedAmount > 0, "LOVELY ILO: User dont make deposit in stake");
        require(
            userBonus[msg.sender].depositedTime + ((86400 / oneBlockCreationTime) * 5) < block.number,
            "LOVELY ILO: You cannot yet claim a bonus"
        );
        require(userBonus[msg.sender].claimings < 2, "LOVELY ILO: User claimed all bonuses");
        uint256 claimAmount = (((totalCap * saleInformation.presaleRate) / usersLenght) / saleInformation.extraQuantity) / 2;
        IERC20 iloToken = IERC20(saleInformation._salesToken.token);
        
        if (userBonus[msg.sender].claimings == 1) {
            require(
                userBonus[msg.sender].depositedTime + ((86400 / oneBlockCreationTime) * 15) < block.number,
                "LOVELY ILO: User cant get second amount of bonus yet"
            );
            iloToken.transfer(msg.sender, claimAmount);
            userBonus[msg.sender].claimings++;
            emit ClaimBonus(msg.sender, claimAmount);
            return;
        }

        iloToken.transfer(msg.sender, claimAmount);
        userBonus[msg.sender].claimings++;

        emit ClaimBonus(msg.sender, claimAmount);
    }

    /**
     * Function allows to deposit purche or native token
     * @param _amount amount of deposit
     */
    function deposit(uint256 _amount) external payable {
        //checks that user not deposit yet
        require(users[msg.sender].depositedAmount == 0, "LOVELY ILO: The user has already deposited");

        //checks that deposit amount more that minimum contribution and less than maximum contribution limit
        require(
            _amount >= saleInformation.minContributionLimit,
            "LOVELY ILO: Deposit amount should be more than minimum contribution limit"
        );
        require(
            _amount <= saleInformation.maxContributionLimit,
            "LOVELY ILO: Deposit amount should be less than maximum contribution limit"
        );

        require(
            totalCap + _amount <= saleInformation.hardCap,
            "LOVELY ILO: the amount of tokens in the contract will exceeds the total cap"
        );

        require(block.number >= saleInformation.startDepositTime, "LOVELY ILO: Sale not started");
        require(block.number < saleInformation.endDepositTime, "LOVELY ILO: Sale end");

        uint depositAmount = 0;

        if (!saleInformation.useNativeToken) {
            IERC20 token = IERC20(purchaseToken.token);
            require(token.balanceOf(msg.sender) >= _amount, "LOVELY ILO: Insufficient balance");
            token.transferFrom(msg.sender, address(this), _amount);

            depositAmount = _amount;
        } else {
            depositAmount = msg.value;
        }

        users[msg.sender].depositedAmount = depositAmount;
        totalCap += depositAmount;
        usersLenght += 1;

        emit Deposit(msg.sender, depositAmount);
    }

    /**
     * Function allows users get ILO tokens if they have made deposit
     */
    function claim() external nonReentrant payable {
        //cant calim if soft cap not reached
        require(totalCap >= saleInformation.softCap, "LOVELY ILO: Soft cap not reached");

        //cant claim if deposit time not ended
        require(block.number > saleInformation.endDepositTime, "LOVELY ILO: sale not ended");

        //cant calim if user not deposited or already claimed
        require(users[msg.sender].depositedAmount > 0, "LOVELY ILO: User not make any deposit");
        require(users[msg.sender].claimed == false, "LOVELY ILO: Already claimed");

        ERC20 purchase = ERC20(purchaseToken.token);
        ERC20 sales = ERC20(saleInformation._salesToken.token);
        uint256 salesDecimals = sales.decimals();
        uint256 purchaseDecimals = purchase.decimals();
        //calculating claim amount
        uint256 claimAmount = users[msg.sender].depositedAmount * saleInformation.presaleRate;
        if (purchaseDecimals > salesDecimals) {
            claimAmount = claimAmount / (10 ** (purchaseDecimals - salesDecimals));
        } else if (purchaseDecimals < salesDecimals) {
            claimAmount = claimAmount / (10 ** (salesDecimals - purchaseDecimals));
        }

        //transfer money
        IERC20 token = IERC20(saleInformation._salesToken.token);
        token.transfer(msg.sender, claimAmount);

        users[msg.sender].claimed = true;

        emit Claim(msg.sender, claimAmount);
    }

    function unstakeBonus(uint256 amount) external payable {
        require(amount > 0, "LOVELY ILO: Amount to unstake must be bigger then zero");
        require(userBonus[msg.sender].depositedAmount >= amount, "LOVELY ILO: Low user balance in staking");
        StakingContract.unstake(amount);

        IERC20 lovey = IERC20(LOVELYTokenAddress);
        assert(lovey.transfer(msg.sender, amount));
        userBonus[msg.sender].depositedAmount -= amount;
        
        emit UnstakeBonus(amount);
    }

    /**
     * Add a new manager in sale
     * 
     * @param _manager address of new sale manager
     */
    function managerAdd(address _manager) external onlyOwner(msg.sender, owner) isManagerAlreadyExist(_manager, managers) {
        managers[_manager] = true;

        emit AddManager(_manager);
    }

    function getUserBonusAmount() external view returns(uint256) {
        return userBonus[msg.sender].depositedAmount;
    }

    /**
     * Delete existing sale manager
     * 
     * @param _manager address of existing sale manager
     */
    function managerRemove(address _manager) external onlyOwner(msg.sender, owner) isManagerExist(_manager, managers) {
        delete managers[_manager];

        emit RemoveManager(_manager);
    }

    /**
     * Checks for existing manager
     */
    function isManager(address _manager) external view returns(bool) {
        return managers[_manager];
    }

    /**
     * Updatest start deposit time
     * 
     * @param _block block number for update start
     */
    function updateStartDepositTime(uint256 _block) external onlyOwnerOrManager(msg.sender, owner, managers) blockDuration(_block, saleInformation.endDepositTime, oneBlockCreationTime) {
        require(block.number < saleInformation.startDepositTime, "LOVELY ILO: Deposit already started");

        saleInformation.startDepositTime = _block;

        emit UpdateStartDepositTime(_block);
    }

    /**
     * Updatest end deposit time
     * 
     * @param _block block number for update end
     */
    function updateEndDepositTime(uint256 _block) external onlyOwnerOrManager(msg.sender, owner, managers) blockDuration(saleInformation.startDepositTime, _block, oneBlockCreationTime) {
        require(block.number < saleInformation.startDepositTime, "LOVELY ILO: Deposit already started");

        saleInformation.endDepositTime = _block;

        emit UpdateEndDepositTime(_block);
    }

    /**
     * Transfers the purchase token in the right percentages
     */
    function withdrawTokenRewards() external onlyOwner(msg.sender, owner) {
        require(saleInformation.endDepositTime <= block.number, "LOVELY ILO: Sale not end yet"); 

        uint256 stakingReward = totalCap * 125 / 10000;
        uint256 iloFees = totalCap * 1125 / 10000;
        uint256 dexLiquidity = totalCap * 475 / 1000;
        uint256 client = totalCap * 40 / 100;

        _transferToDexPool(dexLiquidity);
        _transferToStaking(stakingReward);
        _transferToLaunchpad(iloFees);
        _transferToClient(client);

        emit WithdrawTokenRewards(client);
    }

    /**
     * Returns amount of tokens to approve
     */
    function getBonusAprovalAmount(address user) public view returns(uint256) {
        uint256 inStakeAmount = users[user].depositedAmount / 2;
        if (saleInformation.useNativeToken || (purchaseToken.token != LOVELYTokenAddress)) {
            uint256 amount = _transformToken(inStakeAmount);
            return amount;
        }
        return inStakeAmount;
    }

    /**
     * Function that allows to transfer tokens as liquidity
     * 
     * @param _amount amount of tokens
     */
    function _transferToDexPool(uint256 _amount) internal {
        FactoryContract.createValidatedPair(
            purchaseToken.token,
            saleInformation._salesToken.token,
            LOVELYTokenAddress,
            0,
            0
        );

        IERC20 pu = IERC20(purchaseToken.token);
        IERC20 se = IERC20(saleInformation._salesToken.token);
        uint256 puAmount = _amount;

        uint256 salesAmount = totalCap / saleInformation.presaleRate;

        pu.approve(RouterContractAddress, puAmount);
        se.approve(RouterContractAddress, salesAmount);

        uint256 u = block.timestamp + 3600;
        if (!saleInformation.useNativeToken) {
            RouterContract.addLiquidity(
                purchaseToken.token,
                saleInformation._salesToken.token,
                puAmount,
                salesAmount,
                0,
                0,
                address(this),
                u
            );
        } else {
            RouterContract.addLiquidityETH{value: puAmount}(
                saleInformation._salesToken.token,
                salesAmount,
                0,
                0,
                address(this),
                u
            );
        }
    }

    /**
     * Function that allows transfer money from ilo to staking as reward
     * 
     * @param _amount amount of tokens
     */
    function _transferToStaking(uint256 _amount) internal {
        uint256 amount = _amount;
        if (!saleInformation.useNativeToken) {
            if (purchaseToken.token != LOVELYTokenAddress) {
                address[] memory path = _getSwapPath(USDTTokenAddress, LOVELYTokenAddress);
                ERC20 usdt = ERC20(USDTTokenAddress);
                usdt.approve(RouterContractAddress, _amount);
                uint[] memory amounts = RouterContract.swapExactTokensForTokens(
                    _amount,
                    0,
                    path,
                    address(this),
                    block.timestamp + 3600
                );
                amount = amounts[amounts.length - 1];
            }
        } else {
            address weth = RouterContract.WETH();
            address[] memory path = _getSwapPath(weth, LOVELYTokenAddress);
            uint[] memory amounts = RouterContract.swapExactETHForTokens{value: _amount}(
                0,
                path,
                address(this),
                block.timestamp + 3600
            );
            amount = amounts[amounts.length - 1];
        }

        IERC20 lovely = IERC20(LOVELYTokenAddress);
        lovely.approve(LOVELYStakeContractAddress, amount);

        StakingContract.addRewardAmount(amount);
    }

    /**
     * Function that transfers tokens in Launcpad contract
     * 
     * @param _amount amount of tokens to transfer
     */
    function _transferToLaunchpad(uint256 _amount) internal {
        if (!saleInformation.useNativeToken) {
            if (purchaseToken.token != LOVELYTokenAddress) {
                _transferHelper(IERC20(USDTTokenAddress), _LOVELYLaunchpad, _amount);
                return;
            }
            _transferHelper(IERC20(LOVELYTokenAddress), _LOVELYLaunchpad, _amount);
            return;
        }
        LOVELYLaunchpad launchpad = LOVELYLaunchpad(_LOVELYLaunchpad);
        launchpad.transfer{value: _amount}();
    }

    /**
     * Helpto transfer tokens safly
     * 
     * @param token ERC20 token contract
     * @param to recepient address
     * @param amount amount of tokens to transfer
     */
    function _transferHelper(IERC20 token, address to, uint256 amount) internal {
        assert(token.transfer(to, amount));
    }

    /**
     * Thansfer tokens to ILO Owner
     * 
     * @param _amount amount of tokens
     */
    function _transferToClient(uint256 _amount) internal {
        if (saleInformation.useNativeToken) {
            payable(msg.sender).transfer(_amount);
        } else {
            IERC20 token = IERC20(purchaseToken.token);
            assert(token.transfer(msg.sender, _amount));
        }
    }

    /**
     * Get amount of tokens that user must to deposit in LOVELY
     * 
     * @param inStakeAmount amount tokens that ILO participant must to deposit
     */
    function _transformToken(uint256 inStakeAmount) internal view returns(uint256) {
        address[] memory path;
        if (purchaseToken.token != LOVELYTokenAddress && !saleInformation.useNativeToken) {
            path = _getSwapPath(USDTTokenAddress, LOVELYTokenAddress);
        }
        if (saleInformation.useNativeToken) {
            address weth = RouterContract.WETH();
            path = _getSwapPath(weth, LOVELYTokenAddress);
        }
        uint[] memory amounts = RouterContract.getAmountsOut(inStakeAmount, path, 0);

        return amounts[amounts.length - 1];
    }

    /**
     * Get path for swap
     * 
     * @param inputTokenAddress token address from which we exchange
     * @param outputTokenAddress token address to which we exchange
     */
    function _getSwapPath(address inputTokenAddress, address outputTokenAddress) internal view returns (address[] memory) {
        address pairAddress = FactoryContract.getPair(inputTokenAddress, outputTokenAddress);
        
        address[] memory path;
        if (pairAddress != address(0)) {
            path = new address[](2);
            path[0] = inputTokenAddress; path[1] = outputTokenAddress;
            return path;
        }
        
        path = new address[](3);
        address intermediate = _getIntermediateTokenAddress(inputTokenAddress, outputTokenAddress);
        require(intermediate != address(0), "LOVELY ILO: Pool USDT - XYZ - LOVELY don't exist");
        path[0] = inputTokenAddress; path[1] = intermediate; path[2] =  outputTokenAddress;
        return path;
    }

    /**
     * Get intermediate address for swap path
     * 
     * @param inputTokenAddress token address from which we exchange
     * @param outputTokenAddress token address to which we exchange
     */
    function _getIntermediateTokenAddress(address inputTokenAddress, address outputTokenAddress) internal view returns (address) {     
        LOVELYTokenList tokenList = LOVELYTokenList(FactoryContract.getTokenList());

        uint256 left = 0;
        uint256 right = tokenList.length() -1;
        while (left <= right) {
            address tokenAddress = tokenList.at(left);
            address pair1 = FactoryContract.getPair(inputTokenAddress, tokenAddress);
            address pair2 = FactoryContract.getPair(tokenAddress, outputTokenAddress);
            
            if (pair1 != address(0) && pair2 != address(0)) {
                return tokenAddress;
            } else {
                left += 1;
            }
        }
        
        return address(0);
    }
}