//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title IDO contract.
 * @author Pavel E. Hrushchev (DrHPoint).
 * @notice You can use this contract for working with IDO.
 * @dev All function calls are currently implemented without side effects.
 */
contract IDO is AccessControl {
    event CreateCampaign(
        uint256 indexed campaignId,
        uint256 minAllocation,
        uint256 maxAllocation,
        uint256 minGoal,
        uint256 maxGoal,
        uint256 price,
        uint256 startTime,
        uint256 endTime,
        address acquireAddress,
        address rewardAddress,
        uint8 acquireDecimals,
        uint8 rewardDecimals
    );

    event ApproveCampaign(uint256 indexed campaignId, string decision);

    event Join(
        uint256 indexed campaignId,
        address indexed user,
        uint256 amount,
        address token
    );

    event Refund(
        uint256 indexed campaignId,
        address indexed user,
        uint256 amount,
        address token
    );

    event Claim(
        uint256 indexed campaignId,
        address indexed user,
        uint256 amount,
        address token
    );

    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 private precision = 1e18;
    uint256 private precisionPrice = 1e18;
    uint256 public counter;

    mapping(uint256 => Campaign) campaigns;
    mapping(uint256 => Vesting[]) vestings;
    mapping(uint256 => mapping(address => AllocationAndClaim)) users;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    enum Status {
        Actual,
        ReadyToClaim,
        Refunding
    }

    struct AllocationAndClaim {
        uint256 allocation;
        uint256 toClaim;
        uint256 claimed;
    }

    struct Vesting {
        uint256 percent;
        uint256 timestamp;
    }

    struct Campaign {
        uint256 minAllocation;
        uint256 maxAllocation;
        uint256 minGoal;
        uint256 maxGoal;
        uint256 total;
        uint256 price;
        uint256 startTime;
        uint256 endTime;
        address acquireAddress;
        address rewardAddress;
        uint8 acquireDecimals;
        uint8 rewardDecimals;
        Status status;
    }

    function create(Campaign calldata _campaign, Vesting[] calldata _vestings)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(
            _campaign.minAllocation <= _campaign.maxAllocation,
            "minAllocation should be less or equal then maxAllocation"
        );
        require(
            _campaign.minGoal <= _campaign.maxGoal,
            "minAllocation should be less or equal then maxAllocation"
        );
        require(
            block.timestamp <= _campaign.startTime,
            "Time of start should be more, then current time"
        );
        require(
            _campaign.startTime < _campaign.endTime,
            "Time of start should be less, then end time"
        );
        uint256 pointer = _vestings.length;
        Campaign storage campaign = campaigns[counter];
        campaign.acquireAddress = _campaign.acquireAddress;
        campaign.rewardAddress = _campaign.rewardAddress;
        campaign.acquireDecimals = _campaign.acquireDecimals;
        campaign.rewardDecimals = _campaign.rewardDecimals;
        campaign.minAllocation = _campaign.minAllocation;
        campaign.maxAllocation = _campaign.maxAllocation;
        campaign.minGoal = _campaign.minGoal;
        campaign.maxGoal = _campaign.maxGoal;
        if (_campaign.acquireDecimals >= _campaign.rewardDecimals)
            campaign.price =
                _campaign.price /
                (10**(_campaign.acquireDecimals - _campaign.rewardDecimals));
        else {
            campaign.price = _campaign.price;
            precisionPrice /= (10 **
                (_campaign.rewardDecimals - _campaign.acquireDecimals));
        }
        campaign.startTime = _campaign.startTime;
        campaign.endTime = _campaign.endTime;
        for (uint256 i = 0; i < pointer; i++) {
            if (i != 0) {
                require(_vestings[i].percent > _vestings[i - 1].percent);
                require(_vestings[i].timestamp > _vestings[i - 1].timestamp);
            }
            vestings[counter].push(
                Vesting(
                    _vestings[i].percent,
                    _vestings[i].timestamp + campaign.endTime
                )
            );
        }
        require(
            _vestings[pointer - 1].percent == precision,
            "Last percent isnt equal full sum"
        );
        emit CreateCampaign(
            counter++,
            campaign.minAllocation,
            campaign.maxAllocation,
            campaign.minGoal,
            campaign.maxGoal,
            campaign.price,
            campaign.startTime,
            campaign.endTime,
            campaign.acquireAddress,
            campaign.rewardAddress,
            campaign.acquireDecimals,
            campaign.rewardDecimals
        );
        campaign.status = Status.Actual;
    }

    function approve(uint256 _campaignId) external onlyRole(ADMIN_ROLE) {
        Campaign storage campaign = campaigns[_campaignId];
        require(campaign.endTime <= block.timestamp, "Too early for approve");
        require(campaign.status == Status.Actual, "Not actual campaign");
        if (campaign.total < campaign.minGoal)
        {
            campaign.status = Status.Refunding;
            emit ApproveCampaign(_campaignId, "Refund");
        }
        else {
            campaign.status = Status.ReadyToClaim;
            IERC20(campaign.acquireAddress).safeTransfer(
                msg.sender,
                campaign.total
            );
            emit ApproveCampaign(_campaignId, "Claim");
        }
    }

    function join(uint256 _campaignId, uint256 _amount) external {
        Campaign storage campaign = campaigns[_campaignId];
        require(
            (campaign.startTime < block.timestamp) &&
                (campaign.endTime > block.timestamp),
            "Not right time to join this campaign"
        );
        require(_amount > 0, "Zero amount");
        require(
            campaign.total + _amount <= campaign.maxGoal,
            "Amount together with the current sum exceeds the max goal"
        );
        AllocationAndClaim storage user = users[_campaignId][msg.sender];
        require(
            user.allocation + _amount <= campaign.maxAllocation,
            "Amount together with the current user sum exceeds the max allocation"
        );
        IERC20(campaign.acquireAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        user.allocation += _amount;
        user.toClaim += (_amount * precisionPrice) / campaign.price;
        campaign.total += _amount;
        emit Join(_campaignId, msg.sender, _amount, campaign.acquireAddress);
    }

    function refund(uint256 _campaignId) external {
        Campaign storage campaign = campaigns[_campaignId];
        require(
            campaign.status == Status.Refunding,
            "This campaign already not refunding"
        );
        AllocationAndClaim storage user = users[_campaignId][msg.sender];
        require(
            user.allocation > 0,
            "User already refunded all sum or not joined in this campaign"
        );
        IERC20(campaign.acquireAddress).safeTransfer(
            msg.sender,
            user.allocation
        );
        campaign.total -= user.allocation;
        emit Refund(_campaignId, msg.sender, user.allocation, campaign.acquireAddress);
        user.allocation = 0;
    }

    function claim(uint256 _campaignId) external {
        Campaign storage campaign = campaigns[_campaignId];
        require(
            campaign.status == Status.ReadyToClaim,
            "This campaign already not claiming"
        );
        uint256 amount = _sumClaim(_campaignId, msg.sender);
        require(amount > 0, "Already nothing to claim");
        users[_campaignId][msg.sender].claimed += amount;
        IERC20(campaign.rewardAddress).safeTransfer(msg.sender, amount);
        emit Refund(_campaignId, msg.sender, amount, campaign.rewardAddress);
    }

    function availableSum(uint256 _campaignId)
        external
        view
        returns (uint256 amount)
    {
        Campaign storage campaign = campaigns[_campaignId];
        AllocationAndClaim storage user = users[_campaignId][msg.sender];
        if (user.allocation < campaign.maxAllocation)
            amount = campaign.maxAllocation - user.allocation;
        if (amount > campaign.maxGoal - campaign.total)
            amount = campaign.maxGoal - campaign.total;
    }

    function availableToClaim(uint256 _campaignId)
        external
        view
        returns (uint256 generally, uint256 current)
    {
        AllocationAndClaim storage user = users[_campaignId][msg.sender];
        generally = user.toClaim - user.claimed;
        current = _sumClaim(_campaignId, msg.sender);
    }

    function getCampaign(uint256 _campaignId)
        external
        view
        returns (Campaign memory campaign, Vesting[] memory vesting)
    {
        campaign = campaigns[_campaignId];
        if (campaign.acquireDecimals >= campaign.rewardDecimals)
            campaign.price *=
                10**(campaign.acquireDecimals - campaign.rewardDecimals);
        vesting = vestings[_campaignId];
    }

    function getUser(uint256 _campaignId, address _userAddress)
        external
        view
        returns (AllocationAndClaim memory user)
    {
        user = users[_campaignId][_userAddress];
    }

    function _sumClaim(uint256 _campaignId, address _userAddress)
        internal
        view
        returns (uint256 summary)
    {
        AllocationAndClaim storage user = users[_campaignId][_userAddress];
        require(user.claimed != user.toClaim, "All sum already claimed");
        Vesting[] storage vestingss = vestings[_campaignId];
        uint256 currentTime = block.timestamp;
        uint256 count;
        for (; count < vestingss.length; count++)
            if (vestingss[count].timestamp > currentTime) break;
        if (count > 0)
            summary =
                (user.toClaim * vestingss[count - 1].percent) /
                precision -
                user.claimed;
    }
}
