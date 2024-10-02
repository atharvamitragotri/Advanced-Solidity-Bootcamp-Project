// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./Roles.sol";
import "./StakingToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Staking is StakingToken, Roles, ReentrancyGuard {
    IERC20 public stakingToken;

    uint256 public immutable minStakeAmount = 1 * 10**18;
    uint256 public immutable maxStakeAmount = 1000 * 10**18; 
    uint256 public constant COOLDOWN_PERIOD = 7 days;
    address public immutable feeAddress;

    // Fee (in basis points)
    uint256 public stakeFee; 

    bool public paused;

    struct Stake {
        uint256 amount; 
        uint256 rewardAccrued; 
        uint256 lastStakedTime; 
    }

    mapping(address => Stake) public stakes;

    // Annual Percentage Yield (APY) in basis points, 10%
    uint256 public APY = 1000;

    uint256 public totalStaked;
    uint256 public feeAccumulated;


    event Staked(address indexed user, uint256 amount, uint256 fee);
    event Unstaked(address indexed user, uint256 amount, uint256 reward);
    event RewardClaimed(address indexed user, uint256 reward);
    event APYChanged(uint256 newAPY);
    event FeeChanged(uint256 newStakeFee);

    error InvalidAmount(uint256 amount);
    error TokenTransferFailed(address user);
    error NotPauserRole();

    constructor( 
    uint256 _stakeFee,
    address _feeAddress,
    uint256 initialSupply,
    address _priceFeed
) StakingToken(initialSupply, _priceFeed) {
    stakeFee = _stakeFee;
    feeAddress = _feeAddress;
    paused = false;

    // setRole(msg.sender, 0, true);
}
    
    //modifiers

    modifier onlyAdmin() {
        require(hasRole(msg.sender, 0), "Caller is not an admin");
        _;
    }

    modifier onlyPauser() {
        require(hasRole(msg.sender, 1), "Caller is not a Pauser");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier cooldownElapsed(address user) {
        require(block.timestamp >= stakes[user].lastStakedTime + COOLDOWN_PERIOD, "Cooldown period not passed");
        _;
    }
    //functions

    function hasRole(address user, uint8 role) internal view returns (bool) {
    return Roles._hasRole(user, role);
}

    function setFee(uint256 _stakeFee) external onlyAdmin {
        require(_stakeFee <= 1000, "Stake fee too high"); 
        stakeFee = _stakeFee;
        emit FeeChanged(_stakeFee);
    }

    function setAPY(uint256 _newAPY) external onlyAdmin {
        APY = _newAPY;
        emit APYChanged(_newAPY);
    }

    function stake(uint256 _amount) external whenNotPaused {
        if(_amount < minStakeAmount || _amount > maxStakeAmount)
        {
            revert InvalidAmount(_amount);
        } 

        Stake storage userStake = stakes[msg.sender];

        if (userStake.amount > 0) {
            uint256 pendingReward = calculateReward(msg.sender);
            userStake.rewardAccrued += pendingReward;
        }

        uint256 feeAmount = (_amount * stakeFee + 9999) / 10000; 
        feeAccumulated += feeAmount;
        uint256 netAmount = _amount - feeAmount;

        require(
            stakingToken.transferFrom(msg.sender, address(this), _amount),
            "Token transfer failed"
        );

        userStake.amount += netAmount;
        userStake.lastStakedTime = block.timestamp;
        totalStaked += netAmount;

        emit Staked(msg.sender, netAmount, feeAmount);
    }

    function unstake(uint256 _amount) external whenNotPaused cooldownElapsed(msg.sender) nonReentrant { 
        Stake storage userStake = stakes[msg.sender];
        if(userStake.amount < _amount) {
            revert("Insufficient Staked Amount");
        }

        uint256 pendingReward = calculateReward(msg.sender) + userStake.rewardAccrued;
        userStake.rewardAccrued = 0;
        userStake.lastStakedTime = block.timestamp;

        uint256 totalAmount = _amount + pendingReward;

        userStake.amount -= _amount;
        totalStaked -= _amount;

        stakingToken.transfer(msg.sender, totalAmount);

        emit Unstaked(msg.sender, _amount, pendingReward); 
    }

    function claimReward() external whenNotPaused nonReentrant {
        Stake storage userStake = stakes[msg.sender];
        require(userStake.amount > 0, "No staked tokens");

        uint256 pendingReward = calculateReward(msg.sender) + userStake.rewardAccrued;
        require(pendingReward > 0, "No rewards to claim");

        userStake.rewardAccrued = 0;
        userStake.lastStakedTime = block.timestamp;

        if(!stakingToken.transfer(msg.sender, pendingReward)) {
            revert("Reward Claim Failed");

        }

        emit RewardClaimed(msg.sender, pendingReward);
    }

    function restakeReward() external whenNotPaused {
        Stake storage userStake = stakes[msg.sender];
        require(userStake.amount > 0, "No staked tokens");

        uint256 pendingReward = calculateReward(msg.sender) + userStake.rewardAccrued;
        if(pendingReward == 0) {
            revert("No Rewards To Restake");
        } 

        uint256 feeAmount = (pendingReward * stakeFee + 9999) / 10000;
        feeAccumulated += feeAmount; 
        uint256 netReward = pendingReward - feeAmount;

        userStake.rewardAccrued = 0;
        userStake.amount += netReward;
        userStake.lastStakedTime = block.timestamp;
        totalStaked += netReward;

        emit Staked(msg.sender, netReward, feeAmount);
    }

    function batchStake(address[] calldata users, uint256[] calldata amounts) external whenNotPaused onlyAdmin {
        if(users.length != amounts.length) {
            revert("Length Mismatch");
        }
        for (uint256 i = 0; i < users.length; i++) {
            _adminStake(users[i], amounts[i]);
        }
    }

    function batchUnstake(address[] calldata users, uint256[] calldata amounts) external whenNotPaused onlyAdmin {
        if(users.length != amounts.length) {
            revert("Length Mismatch");
        }
        for (uint256 i = 0; i < users.length; i++) {
            _adminUnstake(users[i], amounts[i]);
        }
    }

    function _adminStake(address user, uint256 amount) internal {
        if(amount < minStakeAmount || amount > maxStakeAmount)
        {
            revert InvalidAmount(amount);
        } 

        Stake storage userStake = stakes[user];

        if (userStake.amount > 0) {
            uint256 pendingReward = calculateReward(user);
            userStake.rewardAccrued += pendingReward;
        }

        uint256 feeAmount = (amount * stakeFee + 9999) / 10000;
        feeAccumulated += feeAmount;
        uint256 netAmount = amount - feeAmount;

        require(
            stakingToken.transferFrom(user, address(this), amount),
            "Token transfer failed"
        );

        userStake.amount += netAmount;
        userStake.lastStakedTime = block.timestamp;
        totalStaked += netAmount;

        emit Staked(user, netAmount, feeAmount);
    }

    function _adminUnstake(address user, uint256 amount) internal cooldownElapsed(user) {
        Stake storage userStake = stakes[user];
        if(userStake.amount < amount) {
            revert("Insufficient Staked Amount");
        } 

        uint256 pendingReward = calculateReward(user) + userStake.rewardAccrued;
        userStake.rewardAccrued = 0;
        userStake.lastStakedTime = block.timestamp;

        uint256 totalAmount = amount + pendingReward;

        userStake.amount -= amount;
        totalStaked -= amount;

        stakingToken.transfer(user, totalAmount);

        emit Unstaked(user, amount, pendingReward);
    }


    function calculateReward(address _user) internal view returns (uint256) {
        Stake storage userStake = stakes[_user];
        uint256 stakingDuration = block.timestamp - userStake.lastStakedTime;

        uint256 reward = (userStake.amount * APY * stakingDuration) / (365 days * 10000);
        return reward;
    }

    function getPendingReward(address _user) external view returns (uint256) {
        Stake storage userStake = stakes[_user];
        if (userStake.amount == 0) {
            return 0;
        }
        uint256 pending = calculateReward(_user) + userStake.rewardAccrued;
        return pending;
    }

    function transferFees() external onlyOwner {
        uint256 feesToTransfer = feeAccumulated;
        feeAccumulated = 0; 

        stakingToken.transfer(feeAddress, feesToTransfer);

    }

    function pause() public virtual {
        if(!hasRole(msg.sender, 1)) {
            revert NotPauserRole();
        }

        paused = true;
    }

     function unpause() public virtual {
        if(!hasRole(msg.sender, 1)) {
        revert NotPauserRole();
    }

        paused = false;
    }

    function getTotalFees() external view returns (uint256) {
        return feeAccumulated;
    }

    fallback() external payable {
        revert();
    }
}

