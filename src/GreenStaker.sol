// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GreenStaker is Ownable{
    using SafeERC20 for IERC20;

    uint256 constant public REWARDS_PER_SECOND_NUMERATOR = 158_440_439;
    uint256 constant public REWARDS_PER_SECOND_DENOMINATOR = 10 ** 17;

    struct UserInfo {
        uint256 balance;
        uint256 stakedAt;
        uint256 reward;
        uint256 withdrawalDate;
        uint8 noticePeriodId;
    }

    struct RewardTokenInfo {
        uint256 yieldBalance;
        bool isWhitelisted;
    }

    struct NoticePeriodInfo {
        uint256 noticePeriod;
        address withdrawalNoticeToken;
    }

    mapping(address => bool) public adminsMapping;
    mapping(address => RewardTokenInfo) public rewardTokensMapping;
    mapping(address => UserInfo) public usersMapping;
    mapping(uint8 => NoticePeriodInfo) noticePeriodsMapping;

    constructor(address _st1wToken, address _st4wToken) Ownable(msg.sender) {
        adminsMapping[msg.sender] = true;

        noticePeriodsMapping[1].noticePeriod = 1 weeks;
        noticePeriodsMapping[1].withdrawalNoticeToken = _st1wToken;

        noticePeriodsMapping[2].noticePeriod = 4 weeks;
        noticePeriodsMapping[2].withdrawalNoticeToken = _st4wToken;
    }

    modifier onlyAdmin {
        require(adminsMapping[msg.sender]);
        _;
    }

    function setTokenWhitelist(address _tokenAddress, bool _isWhiteListed) public onlyOwner {
        rewardTokensMapping[_tokenAddress].isWhitelisted = _isWhiteListed;
    }

    function adminYieldDeposit(address _tokenAddress, uint256 _amount) public onlyAdmin {
        rewardTokensMapping[_tokenAddress].yieldBalance += _amount;
        IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
    }

    function adminModifyNoticePeriod(uint8 _noticePeriod, uint256 _newNoticePeriod) public onlyAdmin {
        noticePeriodsMapping[_noticePeriod].noticePeriod = _newNoticePeriod;
    }

    function depositFirstNotice(address _tokenAddress, uint256 _amount) public {
        deposit(_tokenAddress, _amount, 1);
    }

    function depositSecondNotice(address _tokenAddress, uint256 _amount) public {
        deposit(_tokenAddress, _amount, 2);
    }

    function deposit(address _tokenAddress, uint256 _amount, uint8 _noticePeriodId) internal {
        require(rewardTokensMapping[_tokenAddress].isWhitelisted, "Deposited token not whitelisted");

        UserInfo storage user = usersMapping[msg.sender];
        require(user.balance > 0, "User already staking");

        user.balance = _amount;
        user.stakedAt = block.timestamp;
        user.noticePeriodId = _noticePeriodId;

        IERC20(noticePeriodsMapping[_noticePeriodId].withdrawalNoticeToken).safeTransfer(msg.sender, 1);
        IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
    }

    function getUserReward(UserInfo memory _user) internal pure returns(uint256) {
        return (_user.balance * _user.stakedAt * REWARDS_PER_SECOND_NUMERATOR) / REWARDS_PER_SECOND_DENOMINATOR;
    }

    function requestWithdraw() public {
        UserInfo storage user = usersMapping[msg.sender];
        NoticePeriodInfo memory noticePeriodInfo = noticePeriodsMapping[user.noticePeriodId];

        user.reward = getUserReward(user);
        user.withdrawalDate = block.timestamp + noticePeriodInfo.noticePeriod;
        IERC20(noticePeriodInfo.withdrawalNoticeToken).safeTransferFrom(msg.sender, address(0),1);
    }

    function claim(address _tokenAddress) public {
        UserInfo storage user = usersMapping[msg.sender];
        require(user.withdrawalDate >= block.timestamp, "Cannot withdraw yet");
        
        uint256 totalToTransfer = user.balance + user.reward;
        user.balance = 0;
        user.reward = 0;
        IERC20(_tokenAddress).safeTransfer(msg.sender, totalToTransfer);
    }

    function balanceOf(address _userAddress) public view returns(uint256) {
        return usersMapping[_userAddress].balance;
    }
}
