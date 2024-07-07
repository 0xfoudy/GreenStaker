// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GreenStaker is Ownable{
    using SafeERC20 for IERC20;

    // rewards are 5% per year which is equivalent to (5 / 365.25 * 24 * 60 * 60) = 1.58440439 * 10 ** -9
    uint256 constant public REWARDS_PER_SECOND_NUMERATOR = 158_440_439;
    uint256 constant public REWARDS_PER_SECOND_DENOMINATOR = 10 ** 17;

    /**
     * @notice UserInfo struct representing the details of the user
     * @param balance represents how much the user has staked
     * @param stakedAt represents the timestamp at which the user staked
     * @param reward represents the reward accumulated until the claim request
     * @param withdrawalDate represents the date at which the user is allowed to withdraw
     * @param noticePeriodId represents the notice period which the user chose to stake for
    */
    struct UserInfo {
        uint256 balance;
        uint256 stakedAt;
        uint256 reward;
        uint256 withdrawalDate;
        uint8 noticePeriodId;
    }

    /**
     * @notice RewardTokenInfo struct representing the details of the reward token
     * @param yieldbalance represents the total yield balance of the token
     * @param isWhitelisted represents whether the token is whitelisted or not
    */
    struct RewardTokenInfo {
        uint256 yieldBalance;
        bool isWhitelisted;
    }

     /**
     * @notice NoticePeriodInfo struct representing the details of the many notice periods
     * @param noticePeriod represents the total duration of the notice to be given in weeks
     * @param withdrawalNoticeToken represents the ERC20 to be given on claim request
    */
    struct NoticePeriodInfo {
        uint256 noticePeriod;
        address withdrawalNoticeToken;
    }

    mapping(address => bool) public adminsMapping;
    mapping(address => RewardTokenInfo) public rewardTokensMapping;
    mapping(address => UserInfo) public usersMapping;
    mapping(uint8 => NoticePeriodInfo) noticePeriodsMapping;

    /**
     * @notice constructor used to initialize the contract
     * @param _st1wToken is the address of the first notice token (1 week)
     * @param _st4wToken is the address of the second notice token (4 weeks)
    */
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

    /**
     * @notice setTokenWhitelist function modifies the whitelist status of a token
     * @param _tokenAddress represents address of that token
     * @param _isWhitelisted represents the whitelist status to be set
    */
    function setTokenWhitelist(address _tokenAddress, bool _isWhitelisted) public onlyOwner {
        rewardTokensMapping[_tokenAddress].isWhitelisted = _isWhitelisted;
    }

    /**
     * @notice adminYieldDeposit function lets the admin deposit a specific token as yield
     * @param _tokenAddress represents address of that token
     * @param _amount represents the amount to be deposited
    */
    function adminYieldDeposit(address _tokenAddress, uint256 _amount) public onlyAdmin {
        rewardTokensMapping[_tokenAddress].yieldBalance += _amount;
        IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @notice adminModifyNoticePeriod function lets the admin modify the notice period
     * @param _noticePeriodId represents notice period Id
     * @param _newNoticePeriod represents the notice period to be set (in weeks)
    */
    function adminModifyNoticePeriod(uint8 _noticePeriodId, uint256 _newNoticePeriod) public onlyAdmin {
        noticePeriodsMapping[_noticePeriodId].noticePeriod = _newNoticePeriod;
    }

    /**
     * @notice deposit function lets users deposit a token to stake, it sets the user's parameters, transfers the specific notice token and takes the tokens to be staked.
     * @param _tokenAddress represents address of that token
     * @param _amount represents the amount to be deposited
     * @param _noticePeriodId represents the notice period which the user chose to stake for
    */
    // TODO: allow users to deposit different tokens
    function deposit(address _tokenAddress, uint256 _amount, uint8 _noticePeriodId) public {
        require(rewardTokensMapping[_tokenAddress].isWhitelisted, "Deposited token not whitelisted");

        UserInfo storage user = usersMapping[msg.sender];
        require(user.balance > 0, "User already staking");

        user.balance = _amount;
        user.stakedAt = block.timestamp;
        user.noticePeriodId = _noticePeriodId;

        IERC20(noticePeriodsMapping[_noticePeriodId].withdrawalNoticeToken).safeTransfer(msg.sender, 1);
        IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @notice getUserReward function calculates the users rewards
     * @param _user represents user to have his rewards calculated
    */
    // TODO: get user rewards per token
    function getUserReward(UserInfo memory _user) internal pure returns(uint256) {
        return (_user.balance * _user.stakedAt * REWARDS_PER_SECOND_NUMERATOR) / REWARDS_PER_SECOND_DENOMINATOR;
    }

    /**
     * @notice requestWithdraw function allows the user to request a withdrawal, it sets the withdrawal date according to the noticeId, and burns the notice token
    */
    // TODO: make sure safeTransferFrom works with address(0) as destination
    // TODO: requestWithdraw per token
    function requestWithdraw() public {
        UserInfo storage user = usersMapping[msg.sender];
        NoticePeriodInfo memory noticePeriodInfo = noticePeriodsMapping[user.noticePeriodId];

        user.reward = getUserReward(user);
        user.withdrawalDate = block.timestamp + noticePeriodInfo.noticePeriod;
        IERC20(noticePeriodInfo.withdrawalNoticeToken).safeTransferFrom(msg.sender, address(0),1);
    }

    /**
    * @notice claim function makes sure the user's notice period has passed and transfers the earned reward + initially staked tokens
    * @param _tokenAddress represents address of that token
    */
    function claim(address _tokenAddress) public {
        UserInfo storage user = usersMapping[msg.sender];
        require(user.withdrawalDate >= block.timestamp, "Cannot withdraw yet");
        
        uint256 totalToTransfer = user.balance + user.reward;
        user.balance = 0;
        user.reward = 0;
        IERC20(_tokenAddress).safeTransfer(msg.sender, totalToTransfer);
    }

    /**
    * @notice balanceOf function lets users check the balance of an address
    * @param _userAddress represents address of that user
    */
    function balanceOf(address _userAddress) public view returns(uint256) {
        return usersMapping[_userAddress].balance;
    }
}
