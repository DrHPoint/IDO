//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
//import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract IDO is AccessControl {
    
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 private precision = 1e18;
    uint256 private precisionPrice = 1e18;
    uint256 public counter;

    mapping(uint256 => Campaign) campaigns;
    mapping(uint256 => Vesting[]) vestings;
    mapping(uint256 => mapping(address => AllocationAndClaim)) users;
    
    constructor()
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    enum Status{
        Actual,
        ReadyToClaim,
        Refunding
    }

    struct AllocationAndClaim{
        uint256 allocation;
        uint256 toClaim;
        uint256 claimed;
    }

    struct Vesting{
        uint256 percent;
        uint256 timestamp;
    }

    struct Campaign{
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

    function create(
        Campaign calldata _campaign,
        Vesting[] calldata _vestings
    ) external onlyRole(ADMIN_ROLE) {
        require(_campaign.minAllocation <= _campaign.maxAllocation, "minAllocation should be less or equal then maxAllocation");
        require(_campaign.minGoal <= _campaign.maxGoal, "minAllocation should be less or equal then maxAllocation");
        require(block.timestamp <= _campaign.startTime, "Time of start should be more, then current time");
        
        uint256 pointer = _vestings.length;
        campaigns[counter].acquireAddress = _campaign.acquireAddress; 
        campaigns[counter].rewardAddress = _campaign.rewardAddress;
        campaigns[counter].acquireDecimals = _campaign.acquireDecimals; 
        campaigns[counter].rewardDecimals = _campaign.rewardDecimals; 
        campaigns[counter].minAllocation = _campaign.minAllocation; 
        campaigns[counter].maxAllocation = _campaign.maxAllocation; 
        campaigns[counter].minGoal = _campaign.minGoal; 
        campaigns[counter].maxGoal = _campaign.maxGoal;
        if (_campaign.acquireDecimals >= _campaign.rewardDecimals)
            campaigns[counter].price = _campaign.price /  (10 ** (_campaign.acquireDecimals - _campaign.rewardDecimals)); 
        else 
        {
            campaigns[counter].price = _campaign.price; 
            precisionPrice /= (10 ** (_campaign.rewardDecimals - _campaign.acquireDecimals));
        }
        campaigns[counter].startTime = _campaign.startTime; 
        campaigns[counter].endTime = _campaign.endTime;
        for(uint256 i = 0; i < pointer; i++) {
            if (i != 0)
            {
                require(_vestings[i].percent > _vestings[i - 1].percent);
                require(_vestings[i].timestamp > _vestings[i - 1].timestamp);
            }
            vestings[counter].push(Vesting(_vestings[i].percent, _vestings[i].timestamp + campaigns[counter].endTime));
        }
        require(_vestings[pointer - 1].percent == precision, "Last percent isnt equal full sum");
        campaigns[counter++].status = Status.Actual;
    }

    function approve(uint256 _campaignId) external onlyRole(ADMIN_ROLE) {
        Campaign storage campaign = campaigns[_campaignId];
        require(campaign.endTime <= block.timestamp, "Too early for approve");
        require(campaign.status == Status.Actual, "Not actual campaign");
        if (campaign.total < campaign.minGoal)
            campaign.status = Status.Refunding;
        else
        {
            campaign.status = Status.ReadyToClaim;
            IERC20(campaign.acquireAddress).safeTransfer(msg.sender, campaign.total);
        }
    }

    function join(uint256 _campaignId, uint256 _amount) external {
        Campaign storage campaign = campaigns[_campaignId];
        require((campaign.startTime < block.timestamp)&&(campaign.endTime > block.timestamp), "Not right time to join this campaign");
        require(campaign.total < campaign.maxGoal, "Goal amount already collected");
        require(_amount >= campaign.minAllocation && _amount <= campaign.maxAllocation, "Zero amount");
        AllocationAndClaim storage user = users[_campaignId][msg.sender];
        require(user.allocation < campaign.maxAllocation, "User have max allocation");
        uint256 amount = _amount;
        if (user.allocation + _amount > campaign.maxAllocation)
            amount = campaign.maxAllocation - user.allocation;
        if (campaign.maxGoal - campaign.total < amount)
            amount = campaign.maxGoal - campaign.total;
        IERC20(campaign.acquireAddress).safeTransferFrom(msg.sender, address(this), amount);
        user.allocation += amount;
        user.toClaim += amount * precisionPrice / campaign.price;
        campaign.total += amount;
        //Добавить requires для превышения макс аллокашина
    }

    function refund(uint256 _campaignId) external {
        Campaign storage campaign = campaigns[_campaignId];
        require(campaign.status == Status.Refunding, "This campaign already not refunding");
        AllocationAndClaim storage user = users[_campaignId][msg.sender];
        require(user.allocation > 0, "User already refunded all sum or not joined in this campaign");
        IERC20(campaign.acquireAddress).safeTransfer(msg.sender, user.allocation);
        campaign.total -= user.allocation;
        user.allocation = 0;
    }

    function claim(uint256 _campaignId) external {
        Campaign storage campaign = campaigns[_campaignId];
        require(campaign.status == Status.ReadyToClaim, "This campaign already not claiming");
        uint256 amount = _sumClaim(_campaignId, msg.sender);
        require(amount > 0, "Already nothing to claim");
        users[_campaignId][msg.sender].claimed += amount;
        IERC20(campaign.rewardAddress).safeTransfer(msg.sender, amount);
    }

    function _sumClaim(uint _campaignId, address _userAddress) internal view returns (uint256 summary){
        AllocationAndClaim storage user = users[_campaignId][_userAddress];
        require(user.claimed != user.toClaim, "All sum already claimed");
        Vesting[] storage vestingss = vestings[_campaignId];
        uint256 currentTime = block.timestamp;
        uint256 count;
        for (; count < vestingss.length; count++)
            if(vestingss[count].timestamp > currentTime)
                break;
        if (count > 0)
            summary = (user.toClaim * vestingss[count - 1].percent) / precision - user.claimed;
    }

    
}