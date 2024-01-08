// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.15;

import "./interfaces/ILOVELYTokenList.sol";
import "./LOVELYAuditedRouter.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
    @title The trading competitions factory.

    @dev The competition's lifecycle works according to the following state machine:
        1. Initially, the competition is created using the "Registration" status.
        2. Then, the competition can be moved to the "Open" status meaning that the competition has started
        and the competition router should be used for processing transactions.
        3. Then, the competition moves to the "Close" state meaning that it has ended.
        4. After that, the competition can be announced as "Claiming". While moving to this status, the leaders are calculated and stored.
        5. Finally, the competition moves to the "Over" state which is the final state in which nothing more will happen to the competition.

    The competition's winners are determined on-chain to provide the most fair judgement.
    To accomplish this, the LOVELYAuditedRouted is used to track all transaction amounts during the competition.
 */
contract LOVELYCompetition is ILOVELYAddressFilter {

    // Competition event status for the campaign state machine.
    enum Status {
        Registration,
        Open,
        Close,
        Claiming,
        Over
    }

    // Competition event winners tier.
    enum Tier {
        Zero,
        First,
        Second,
        Third
    }

    // Competition even memory slot.
    struct Event {

        // Event status.
        Status status;

        // Event start block.
        uint256 startBlock;

        // Event end block.
        uint256 endBlock;

        // Total reward amount for event winners.
        uint256 rewardAmount;

        // Event reward token.
        address rewardToken;

        // Event creator
        address creator;

        // A reference to the audited router.
        LOVELYAuditedRouter router;

        // Event tier reward percentages.
        mapping(Tier => uint256) tiers;

        // Event participants.
        mapping(address => User) users;

        // Event winners.
        address[] winners;
    }

    // Competition participant user memory slot.
    struct User {

        // Whether the user is registered to an event.
        bool registered;

        // Whether the user has claimed his reward.
        bool claimed;
    }

    /**
        Count of events, created by this factory.
     */
    uint256 public eventCount;

    /**
        Minimum reward amount for an event.
     */
    uint256 public minimumRewardAmount;

    /**
        A reference to the DEX factory to be able to access DEX.
     */
    address public immutable factory;

    /**
        A reference to the WETH contract to be able to create a router.
     */
    address public immutable WETH;

    /**
        The winners tier count being 4.
     */
    uint256 private constant TIER_COUNT = 4;

    /**
        The index of a last zero-tier user.
     */
    uint256 private constant ZERO_TIER_LAST_USER_INDEX = 5;

    /**
        The index of a last first-tier user.
     */
    uint256 private constant FIRST_TIER_LAST_USER_INDEX = 10;

    /**
        The index of a last second-tier user.
     */
    uint256 private constant SECOND_TIER_LAST_USER_INDEX = 20;

    /**
        Just 100% (the total single).
     */
    uint256 private constant PERCENTAGE_TOTAL = 100;

    /**
        Zero-tier user count.
     */
    uint256 private constant ZERO_TIER_USER_COUNT = 5;

    /**
        First-tier user count.
     */
    uint256 private constant FIRST_TIER_USER_COUNT = 5;

    /**
        Second-tier user count.
     */
    uint256 private constant SECOND_TIER_USER_COUNT = 10;

    /**
        Third-tier user count.
     */
    uint256 private constant THIRD_TIER_USER_COUNT = 30;

    /**
        Competition factory owner address.
     */
    address private owner;

    /**
        DEX factory token list address.
     */
    address private tokenList;

    /**
        Events, created by this factory.
     */
    mapping(uint256 => Event) private events;

    /**
        Triggered when event tiers are set.

        @param _eventIdentifier The given competition event identifier.
        @param _tiers The tiers to be set.
     */
    event SetEventTiers(uint256 _eventIdentifier, uint256[TIER_COUNT] _tiers);

    /**
        Triggered when the competition event changes status.

        @param _eventIdentifier The given competition event identifier.
        @param _status The resulting competition event status.
     */
    event EventTransition(uint256 _eventIdentifier, Status _status);

    /**
        Triggered, when a user claims a competition reward.
     */
    event Claim(uint256 _eventIdentifier);

    /**
        Triggered, when a user registers to a competition event.

        @param _eventIdentifier The given competition event identifier.
     */
    event Register(uint256 _eventIdentifier);

    /**
        Triggered, when the administrator changes the minimum reward amount.

        @param _amount The given amount.
     */
    event MinimumRewardAmount(uint256 _amount);

    /**
        Triggered, when a competition event is created.

        @param _startBlock A block, when the competition starts.
        @param _endBlock A block, when the competition ends.
        @param _rewardAmount An total reward amount assigned to all the competition winners.
        @param _rewardToken A reward token.
        @param _tiers Reward percentage assigned to each tier.
     */
    event Create(
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _rewardAmount,
        address _rewardToken,
        uint256[TIER_COUNT] _tiers
    );

    /**
        Apply SafeERC20 to all IERC20 tokens in this contract.
     */
    using SafeERC20 for IERC20;

    /**
        Creates the trading competitions factory.

        @param _factory The DEX factory, to be able to interact with the DEX.
        @param _WETH The WETH token address, to be able to create a router.
        @param _tokenList The token list, to be able to check, whether the participated token is validated on the DEX.
    */
    constructor(address _factory, address _WETH, address _tokenList) {

        require(address(0) != _factory, "LOVELY DEX: ZERO_ADDRESS");
        require(address(0) != _WETH, "LOVELY DEX: ZERO_ADDRESS");
        require(address(0) != _tokenList, "LOVELY DEX: ZERO_ADDRESS");

        owner = msg.sender;
        factory = _factory;
        WETH = _WETH;
        tokenList = _tokenList;
    }

    /**
        Sets the minimum competition reward amount.

        @param _amount The given amount.

        @dev It is not possible to create a competition without assigning a reward more than this given value.
     */
    function setMinimumRewardAmount(uint256 _amount) external {

        require(msg.sender == owner, "LOVELY DEX: FORBIDDEN");

        minimumRewardAmount = _amount;

        emit MinimumRewardAmount(_amount);
    }

    /**
        Creates a competition event.

        Event has given start and end dates defined in the block time.

        Event reward is distributed by tiers according to the following rule:
        _tiers[0] * 5 + _tiers[1] * 5 + _tiers[2] * 10 + _tiers[3] * 30 == 100.
        Tier value contains the percentage of the total reward bank,
        which can be claimed by the winner, who gets into this tier.
        There are:
        - 5 users in the zero tier;
        - 5 users in the 1st tier;
        - 10 users in the 2nd tier;
        - 30 users in the 3d tier.
        The sum of percentages for each rewarded users should, logically, be equal to 100%,
        which is the whole reward bank.
        Tiers can be balanced according to the wish of the one, who creates the competition,
        until these values fall into the above-listed rule.
        For example, only one tier may be defined by setting other tiers to zero percentage.
        Or, tiers can be balanced uniformly or by any other distribution which falls within the given rule.

        @param _startBlock A block, when the competition starts.
        @param _endBlock A block, when the competition ends.
        @param _rewardAmount An total reward amount assigned to all the competition winners.
        @param _rewardToken A reward token.
        @param _tiers Reward percentage assigned to each tier.
    */
    function create(
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _rewardAmount,
        address _rewardToken,
        uint256[TIER_COUNT] calldata _tiers
    ) external {

        // Check that the block range is in the future
        require(block.number <= _startBlock && block.number < _endBlock && _startBlock < _endBlock, "LOVELY DEX: EVENT_BLOCK_RANGE");

        // Check that the reward token is listed and validated
        ILOVELYTokenList list = ILOVELYTokenList(tokenList);
        require(list.validated(_rewardToken), "LOVELY DEX: NOT_VALIDATED");

        // Check that the reward token amount is enough
        require(minimumRewardAmount <= _rewardAmount, "LOVELY DEX: COMPETITION_REWARD_SMALL");

        // Accept the reward amount in the given token
        IERC20(_rewardToken).transferFrom(msg.sender, address(this), _rewardAmount);

        // Validate that tiers are balanced
        require(
            _tiers[0] * ZERO_TIER_USER_COUNT +
            _tiers[1] * FIRST_TIER_USER_COUNT +
            _tiers[2] * SECOND_TIER_USER_COUNT +
            _tiers[3] * THIRD_TIER_USER_COUNT == PERCENTAGE_TOTAL
        , "LOVELY DEX: COMPETITION_TIERS_UNBALANCED");

        uint256 id = eventCount++;
        Event storage competitionEvent = events[id];
        competitionEvent.status = Status.Registration;
        competitionEvent.startBlock = _startBlock;
        competitionEvent.endBlock = _endBlock;
        competitionEvent.rewardAmount = _rewardAmount;
        competitionEvent.rewardToken = _rewardToken;
        competitionEvent.creator = msg.sender;

        competitionEvent.router = new LOVELYAuditedRouter(factory, WETH, _rewardToken);
        setEventTiers(id, _tiers);

        emit Create(_startBlock, _endBlock, _rewardAmount, _rewardToken, _tiers);
    }

    /**
        Returns an audited router corresponding to the given competition event.

        @param _eventIdentifier The given competition event identifier.
     */
    function eventRouter(uint256 _eventIdentifier) external view returns (address) {
        return address(events[_eventIdentifier].router);
    }

    /**
        Returns the given competition event status.

        @param _eventIdentifier The given competition event identifier.
     */
    function eventStatus(uint256 _eventIdentifier) external view returns (Status) {
        return events[_eventIdentifier].status;
    }

    /**
        Returns the given competition event block range (event start and end blocks).

        @param _eventIdentifier The given competition event identifier.
     */
    function eventBlockRange(uint256 _eventIdentifier) external view returns (uint256, uint256) {
        Event storage competitionEvent = events[_eventIdentifier];
        return (competitionEvent.startBlock, competitionEvent.endBlock);
    }

    /**
        Returns the given competition event total reward.

        @param _eventIdentifier The given competition event identifier.
     */
    function eventReward(uint256 _eventIdentifier) external view returns (uint256) {
        return events[_eventIdentifier].rewardAmount;
    }

    /**
        Returns the given competition event reward token.

        @param _eventIdentifier The given competition event identifier.
     */
    function eventRewardToken(uint256 _eventIdentifier) external view returns (address) {
        return events[_eventIdentifier].rewardToken;
    }

    /**
        Returns the given competition event creator.

        @param _eventIdentifier The given competition event identifier.
     */
    function eventCreator(uint256 _eventIdentifier) external view returns (address) {
        return events[_eventIdentifier].creator;
    }

    /**
        Returns the given competition event tiers.

        @param _eventIdentifier The given competition event identifier.
     */
    function eventTiers(uint256 _eventIdentifier) external view returns (uint256[TIER_COUNT] memory) {
        Event storage competitionEvent = events[_eventIdentifier];
        return [
        competitionEvent.tiers[Tier.Zero],
        competitionEvent.tiers[Tier.First],
        competitionEvent.tiers[Tier.Second],
        competitionEvent.tiers[Tier.Third]
        ];
    }

    /**
        Returns the given competition event tier reward.

        @param _eventIdentifier The given competition event identifier.
        @param _tier The given competition event tier.
     */
    function eventTierReward(uint256 _eventIdentifier, Tier _tier) external view returns (uint256) {
        Event storage competitionEvent = events[_eventIdentifier];
        return competitionEvent.rewardAmount * competitionEvent.tiers[_tier] / PERCENTAGE_TOTAL;
    }

    /**
        Transitions the competition event into the next state.

        @param _eventIdentifier The given competition event identifier.

        @dev Transitions to preceding states are not possible.
     */
    function eventTransition(uint256 _eventIdentifier) external {

        require(owner == msg.sender, "LOVELY DEX: FORBIDDEN");

        Event storage competitionEvent = events[_eventIdentifier];
        if (Status.Registration == competitionEvent.status) {
            competitionEvent.status = Status.Open;
        } else if (Status.Open == competitionEvent.status) {
            competitionEvent.status = Status.Close;
        } else if (Status.Close == competitionEvent.status) {
            competitionEvent.winners = competitionEvent.router.topAddresses(50, _eventIdentifier, this);
            competitionEvent.status = Status.Claiming;
        } else if (Status.Claiming == competitionEvent.status) {
            competitionEvent.status = Status.Over;
        }

        emit EventTransition(_eventIdentifier, competitionEvent.status);
    }

    /**
        Returns the list of winners for a given competition event.

        @param _eventIdentifier The given competition event identifier.
     */
    function eventWinners(uint256 _eventIdentifier) external view returns (address[] memory) {

        Event storage competitionEvent = events[_eventIdentifier];

        require(Status.Claiming == competitionEvent.status, "LOVELY DEX: NOT_CLAIMING");

        return competitionEvent.winners;
    }

    /**
        Whether a user is registered in the given competition event.

        @param _eventIdentifier The given competition event identifier.
     */
    function registered(uint256 _eventIdentifier) external view returns (bool) {
        return events[_eventIdentifier].users[msg.sender].registered;
    }

    /**
        For a given address, returns, whether it should be included.

        @param _eventIdentifier The identifier for making a projection within the data source context.
        @param _address The address to be checked.
     */
    function included(uint256 _eventIdentifier, address _address) external view returns (bool) {
        return events[_eventIdentifier].users[_address].registered;
    }

    /**
        Claims trader's reward.

        @param _eventIdentifier The given competition event identifier.

        @dev Claiming the reward IMPLICITLY can be done only for competition events in the "Claiming" state.
        Only the winner can claim.
     */
    function claim(uint256 _eventIdentifier) external {

        Event storage competitionEvent = events[_eventIdentifier];
        User storage user = competitionEvent.users[msg.sender];

        require(user.registered, "LOVELY DEX: NOT_REGISTERED");
        require(!user.claimed, "LOVELY DEX: CLAIMED");

        // Find the trader in the winners array
        bool found = false;
        uint256 length = competitionEvent.winners.length;
        uint256 i = 0;
        for (; i < length; i++) {
            if (msg.sender == competitionEvent.winners[i]) {
                found = true;
                break;
            }
        }

        require(found, "LOVELY DEX: NOT_A_WINNER");

        // Calculate the tier
        Tier tier = Tier.Third;
        if (i < ZERO_TIER_LAST_USER_INDEX) {
            tier = Tier.Zero;
        } else if (i < FIRST_TIER_LAST_USER_INDEX) {
            tier = Tier.First;
        } else if (i < SECOND_TIER_LAST_USER_INDEX) {
            tier = Tier.Second;
        }

        // Calculate the reward
        uint256 reward = competitionEvent.rewardAmount * competitionEvent.tiers[tier] / PERCENTAGE_TOTAL;

        // Mark the trader as one who claimed his reward
        user.claimed = true;

        // Send the prize
        IERC20(competitionEvent.rewardToken).transfer(msg.sender, reward);

        emit Claim(_eventIdentifier);
    }

    /**
        Registers a user in the given competition event.

        @param _eventIdentifier The given competition event identifier.
     */
    function register(uint256 _eventIdentifier) external {

        Event storage competitionEvent = events[_eventIdentifier];
        require(!competitionEvent.users[msg.sender].registered, "LOVELY DEX: HAS_REGISTERED");
        competitionEvent.users[msg.sender].registered = true;

        emit Register(_eventIdentifier);
    }

    /**
        Sets the given competition event tiers.

        @param _eventIdentifier The given competition event identifier.
        @param _tiers The tiers to be set.
     */
    function setEventTiers(uint256 _eventIdentifier, uint256[TIER_COUNT] memory _tiers) private {

        Event storage competitionEvent = events[_eventIdentifier];
        competitionEvent.tiers[Tier.Zero] = _tiers[0];
        competitionEvent.tiers[Tier.First] = _tiers[1];
        competitionEvent.tiers[Tier.Second] = _tiers[2];
        competitionEvent.tiers[Tier.Third] = _tiers[3];

        emit SetEventTiers(_eventIdentifier, _tiers);
    }
}
