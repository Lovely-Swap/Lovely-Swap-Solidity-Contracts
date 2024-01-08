// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity =0.8.15;

import "./LOVELYILO.sol";
import "./LOVELYStaking.sol";
import "./interfaces/ISharedData.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title LOVELY Launchpad factory contract
 * @dev contract to create a new ILO sale
 * @author Eugen K (lineardev.ceo@gmail.com)
 */
contract LOVELYLaunchpad is ISharedData {
    using SafeERC20 for IERC20;

    //owner address
    address internal immutable owner;

    //one block creation time in seconds
    uint256 internal immutable oneBlockCreationTime;

    //staking address
    address public immutable  LOVELYStakingContractAddress;

    //lovely token address
    address public immutable LOVELYTokenAddress;

    //USDT address
    address public immutable USDTTokenAddress;

    //factory contract address
    address public immutable FactoryAddress;

    //router contract address
    address payable immutable RouterAddress;

    //list of created ILOs
    address[] public ilo;

    uint256 public iloLength = 0;

    //minimun duration of singe ILO in seconds = 30 minutes
    uint256 internal constant MIN_ILO_DURATION = 1800;

    //maximum duration of singe ILO in seconds = 7 days
    uint256 internal constant MAX_ILO_DURATION = 604800;
    
    constructor(
        uint256 _oneBlockCreationTime,
        address _FactoryAddress,
        address payable _RouterAddress,
        address LOVELYToken,
        address USDTToken
    ) {
        owner = msg.sender;
        oneBlockCreationTime = _oneBlockCreationTime;
        LOVELYStaking LOVELYStakingContract = new LOVELYStaking(LOVELYToken, _oneBlockCreationTime);
        LOVELYStakingContract.addManager(msg.sender);
        LOVELYTokenAddress = LOVELYToken;
        USDTTokenAddress = USDTToken;
        FactoryAddress = _FactoryAddress;
        RouterAddress = _RouterAddress;
        LOVELYStakingContractAddress = address(LOVELYStakingContract);
    }

    /**
     * Triggers when new ILO was created
     * 
     * @param ilo address of new ILO
     * @param id new ILO id
     */
    event CreateIlo(address indexed ilo, uint256 id);

    /**
     * Triggers if owner claim tokens
     */
    event ClaimAllFees();

    /**
     * Triggers if sombody transfers ETH
     * 
     * @param sender address
     * @param amount transferred amount of ETH
     */
    event ETHTransfered(address sender, uint256 amount);

    /**
     * Function that create new ILO sale
     * 
     * @param params PublicSaleParams from ISharedData.sol
     */
    function createIloContract(
        PublicSaleParams memory params,
        PurchaseToken memory purchase
    ) external returns(address) {
        //check that the parameters are correct
        paramsVerification(params, purchase);

        //Create a new ILO contract and write its address in the array
        address newIlo = address(new LOVELYILO(
            FactoryAddress,
            RouterAddress,
            params,
            purchase,
            oneBlockCreationTime,
            LOVELYStakingContractAddress,
            address(this),
            LOVELYTokenAddress,
            USDTTokenAddress
        ));
        ilo.push(newIlo);
        iloLength += 1;

        uint256 amount = params.hardCap * params.presaleRate;
        uint256 dexLiquidity = amount * 475 / 1000;
        uint256 totalCap = params.extraQuantity != 0 ? amount + (amount / params.extraQuantity) : amount;
        totalCap += dexLiquidity;

        //transger all on ILO contract
        IERC20 salesToken = IERC20(params._salesToken.token);
        salesToken.transferFrom(msg.sender, newIlo, totalCap);

        //add new manager to Staking
        LOVELYStaking staking = LOVELYStaking(LOVELYStakingContractAddress);
        staking.addManager(newIlo);

        //emit event for it
        emit CreateIlo(newIlo, ilo.length - 1);

        //return new ILO sale address
        return newIlo;
    }

    /**
     * Function that allows to owner of contract get fees
     */
    function claimAllFees() public {
        require(msg.sender == owner, "LOVELY Launchpad: Sender not a owner");
        _transferHelper(IERC20(LOVELYTokenAddress), msg.sender);
        _transferHelper(IERC20(USDTTokenAddress), msg.sender);
        payable(msg.sender).transfer(address(this).balance);

        emit ClaimAllFees();
    }

    /**
     * Transfers ETH to Launchpad contract
     */
    function transfer() external payable {
        emit ETHTransfered(msg.sender, msg.value);
    }

    /**
     * The function checks the parameters when creating a new ILO
     * 
     * @param params PublicSaleParams from ISharedData.sol
     */
    function paramsVerification(
        PublicSaleParams memory params,
        PurchaseToken memory purchase
    ) internal view {
        // PublicSaleParams memory pr = params[0];
        //min ilo sale duration
        uint256 minTime = MIN_ILO_DURATION / oneBlockCreationTime;

        //max ilo sale duration
        uint256 maxTime = MAX_ILO_DURATION / oneBlockCreationTime;

        require(params.endDepositTime > params.startDepositTime, "LOVELY Launchpad: Start Time should be less then End Time");
        //current ilo sale duration
        uint256 saleTime;
        unchecked {
            saleTime = params.endDepositTime - params.startDepositTime;
        }

        //check ilo soft and hard cap
        require(params.softCap >= 2106, "LOVELY Launchpad: softCap should be positive number");
        require(params.hardCap >= 2106, "LOVELY Launchpad: hardCap should be positive number");
        require(params.softCap < params.hardCap, "LOVELY Launchpad: softCap should be lower then hardCap");
        require(params.maxContributionLimit < params.hardCap, "LOVELY Launchpad: maxContributionLimit should be less then hardCap");
        //check ilo max and min contribution limit
        require(params.minContributionLimit >= 2106, "LOVELY Launchpad: minContributionLimit should be positive number");
        require(params.maxContributionLimit >= 2106, "LOVELY Launchpad: maxContributionLimit should be positive number");
        require(
            params.minContributionLimit < params.maxContributionLimit, 
            "LOVELY Launchpad: minContributionLimit should be lower then maxContributionLimit"
        );

        //check ilo start and end time
        require(block.number <= params.startDepositTime, "LOVELY Launchpad: Start time should be more then current block");
        require(saleTime >= minTime, "LOVELY Launchpad: The duration of the ILO should be more or equal to 30 minutes");
        require(saleTime <= maxTime, "LOVELY Launchpad: The duration of the ILO should be less or equal to 7 days");

        //paramsesale rate check
        require(params.presaleRate > 0, "LOVELY Launchpad: paramsesaleRate should be positive number");

        //checks that purchase token, sale owner and sales token is not null
        require(params.saleOwner != address(0), "LOVELY Launchpad: saleOwner address cannot be empty");

        //checks it only if we use chain native token
        if(!params.useNativeToken) {
            //checks for correct token address and decimal
            require(purchase.token != address(0), "LOVELY Launchpad: Purchase token address cannot be empty");
        }

        //checks for correct token address and decimal
        require(params._salesToken.token != address(0), "LOVELY Launchpad: Sales token address cannot be empty");
    }

    /**
     * Help transfer all tokens to Launchpad owner
     * 
     * @param token ERCT20 token
     * @param to address of the recipient
     */
    function _transferHelper(IERC20 token, address to) internal {
        uint256 amount = token.balanceOf(address(this));
        if (amount > 0) {
            assert(token.transfer(to, amount));
        }
    }
}
