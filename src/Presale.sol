// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IAggregator.sol";

contract Presale is Ownable {
    using SafeERC20 for IERC20;

    address public saleTokenAddress;
    address public usdtAddress;
    address public usdcAddress;
    address public fundsReceiverAddress;
    address public dataFeedAddress;
    uint256 public maxSellingAmount;
    uint256 public startingTime;
    uint256 public endingTime;
    uint256[][3] public phases;

    uint256 public totalSold;
    uint256 public currentPhase;
    mapping(address => bool) public isBlacklisted;
    mapping(address => uint256) public userTokenBalance;

    event TokenBuy(address user, uint256 amount);


    constructor(address saleTokenAddress_, address usdtAddress_, address usdcAddress_, address fundsReceiverAddress_, address dataFeedAddress_, uint256 maxSellingAmount_, uint256 startingTime_, uint256 endingTime_, uint256[][3] memory phases_) Ownable(msg.sender) {
        saleTokenAddress = saleTokenAddress_;
        usdtAddress = usdtAddress_;
        usdcAddress = usdcAddress_;
        fundsReceiverAddress = fundsReceiverAddress_;
        dataFeedAddress = dataFeedAddress_;
        maxSellingAmount = maxSellingAmount_;
        startingTime = startingTime_;
        endingTime = endingTime_;
        phases = phases_;

        require(endingTime > startingTime, "Incorrect presale times");
        IERC20(saleTokenAddress_).safeTransferFrom(msg.sender, address(this), maxSellingAmount);
    }

    /**
     * Used to blacklist users
     * @param user_ the address of the blacklisted user
     */
    function blackList(address user_) onlyOwner() external {
        isBlacklisted[user_] = true;
    }

    function removeBlacklist(address user_) onlyOwner() external {
        isBlacklisted[user_] = false;
    }

    function checkCurrentPhase(uint256 amount_) private returns(uint256 phase) {
        if((totalSold + amount_ >= phases[currentPhase][0] || (block.timestamp >= phases[currentPhase][2])) && currentPhase < 3) {
            currentPhase++;
            phase = currentPhase;
        } else {
            phase = currentPhase;
        }
    }

    /**
     * Used to buy tokens with stable coin
     * @param tokenUsedToBuy_ the address of the token used to buy
     * @param amount_ the amount of tokens for buying
     */
    function buyWithStable(address tokenUsedToBuy_, uint256 amount_) external {
        require(!isBlacklisted[msg.sender], "User is blacklisted");
        require(block.timestamp >= startingTime && block.timestamp <= endingTime, "Presale not started yet");
        require(tokenUsedToBuy_ == usdtAddress || tokenUsedToBuy_ == usdcAddress, "Incorrect token");

        uint256 tokenAmountToReceive;
        if (ERC20(tokenUsedToBuy_).decimals() == 18) tokenAmountToReceive = amount_ * 1e6 / phases[currentPhase][1];
        else tokenAmountToReceive = amount_ * 10**(18 - ERC20(tokenUsedToBuy_).decimals()) * 1e6  / phases[currentPhase][1];
        checkCurrentPhase(tokenAmountToReceive);

        totalSold += tokenAmountToReceive;
        require(totalSold <= maxSellingAmount, "Sold out");

        // 1 aumentar el balance del usuario
        userTokenBalance[msg.sender] += tokenAmountToReceive;

        // 2 transferir los tokens de venta
        IERC20(tokenUsedToBuy_).safeTransferFrom(msg.sender, fundsReceiverAddress, amount_);

        emit TokenBuy(msg.sender, tokenAmountToReceive);
    }

    function buyWithEther() external payable {
        require(!isBlacklisted[msg.sender], "User is blacklisted");
        require(block.timestamp >= startingTime && block.timestamp <= endingTime, "Presale not started yet");

        uint256 usdValue = msg.value * getEtherPrice() / 1e18;
        uint256 tokenAmountToReceive = usdValue * 1e6 / phases[currentPhase][1];
        checkCurrentPhase(tokenAmountToReceive);

        totalSold += tokenAmountToReceive;
        require(totalSold <= maxSellingAmount, "Sold out");

        userTokenBalance[msg.sender] += tokenAmountToReceive;

        (bool success, ) = fundsReceiverAddress.call{value: msg.value}("");
        require(success, "Transfer fail");

        emit TokenBuy(msg.sender, tokenAmountToReceive);
    }

    function claim() external {
        require(block.timestamp > endingTime, "Presale not ended");

        uint256 amount = userTokenBalance[msg.sender];
        delete userTokenBalance[msg.sender];

        IERC20(saleTokenAddress).safeTransfer(msg.sender, amount);
    }

    function getEtherPrice() public view returns (uint256) {
        (, int256 price,,,) = IAggregator(dataFeedAddress).latestRoundData();
        price =  price * (10 ** 10);
        return uint256(price);
    }

    function emergencyERC20Withdraw(address tokenAddress_, uint256 amount_) onlyOwner external {
        IERC20(tokenAddress_).safeTransfer(msg.sender, amount_);
    }

    function emergencyETHWithdraw() onlyOwner external {
        uint256 balance = address(this).balance;
        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "Transfer fail");
    }
}
