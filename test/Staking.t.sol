// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import "../src/Staking.sol";
import "../src/StakingToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/src/interfaces/feeds/AggregatorV3Interface.sol";

contract StakingTest is Test {
    Staking staking;
    StakingToken stakingToken;
    AggregatorV3Interface priceFeed;

    address user = address(0x1);
    address feeAddress = address(0x2);
    // address immutable ethUSDPriceFeedSepolia = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address immutable ethUSDPriceFeedMainnet = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    function setUp() public {
        priceFeed = AggregatorV3Interface(address(ethUSDPriceFeedMainnet));
        stakingToken = new StakingToken(10000, address(priceFeed));
        staking = new Staking(50, feeAddress, payable(stakingToken)); // 5% fee
    }

    function testStake() public {
        stakingToken.mint{value: 1 ether}(user);
        vm.startPrank(user);

        uint256 initialBalance = stakingToken.balanceOf(user);
        console.log("initialBalance:", initialBalance);
        staking.stake(500*10**18);
        uint256 currentBalance = stakingToken.balanceOf(user);
        console.log("CurrentBalance:", currentBalance);
        assertEq(initialBalance - currentBalance, 500*10**18);
        assertEq(staking.totalStaked(), 500*10**18);

        vm.stopPrank();
    }

    function testUnstake() public {
        testStake(); // Ensure some tokens are staked

        vm.warp(block.timestamp + 8 days); // Move forward in time for cooldown
        staking.unstake(500);

        assertEq(stakingToken.balanceOf(user), 1000); // Returned staked amount
        assertEq(staking.totalStaked(), 0);
    }

    function testStakePausedReverts() public {
        staking.pause();
        vm.expectRevert("Contract is paused");
        staking.stake(500);
    }

    function testCooldownReverts() public {
        testStake();
        vm.expectRevert("Cooldown period not passed");
        staking.unstake(500); // Not enough time elapsed
    }

    function testFeeAccumulation() public {
        testStake();
        assertEq(staking.getTotalFees(), 25); // 5% of 500 = 25
    }

    // Admin: Modify fee and APY

    // Pauser: pause and unpause

    // Modify transfer fee
}
