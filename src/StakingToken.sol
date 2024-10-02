// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/src/interfaces/feeds/AggregatorV3Interface.sol";

contract StakingToken is ERC20, Ownable {

    AggregatorV3Interface internal priceFeed;
    
    event Minted(address user, uint256 amount);
    event Burned(address user, uint256 amount);

    constructor(uint256 initialSupply, address _priceFeed) ERC20("Group6", "G6") {
        _mint(msg.sender, initialSupply);
        priceFeed = AggregatorV3Interface(_priceFeed); 
    }

    // @notice : Get the latest price of ETH in USD
    // returns price with 8 decimals
    function getLatestPrice() public view returns (int) {
        (
            , 
            int price, 
            ,
            ,
        ) = priceFeed.latestRoundData();
        return price; 
    }

    function mint(address user) public payable onlyOwner {
        int ethPrice = getLatestPrice();
        if(ethPrice <= 0) {
            revert("Invalid Price From Chainlink");
        } 

        uint256 tokenAmount = (msg.value * uint256(ethPrice)) / (10 ** 8); 
        _mint(user, tokenAmount);

        emit Minted(user, tokenAmount);
    }

    function burn(address user, uint256 amount) public onlyOwner {
        _burn(user, amount);

        emit Burned(user, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override(ERC20) returns(bool) {
        SafeERC20.safeTransferFrom(IERC20(address(this)), from, to, amount);
        return true;
    }

    receive() external payable {
        revert("Direct ETH transfers not accepted");
    }
}