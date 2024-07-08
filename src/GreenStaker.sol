// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./TemplateERC20.sol";
import "./WithdrawalNFT.sol";


contract GreenStaker is Ownable, Pausable{
    using SafeERC20 for IERC20;

    // rewards are 5% per year which is equivalent to (5 / 365.25 * 24 * 60 * 60) = 1.58440439 * 10 ** -9
    uint256 constant public REWARDS_PER_SECOND_NUMERATOR = 158_440_439;
    uint256 constant public REWARDS_PER_SECOND_DENOMINATOR = 10 ** 17;

    /**
     * @notice UserInfo struct representing the details of the user
     * @param balance represents how much the user has staked
     * @param stakedAt represents the timestamp at which the user staked
     * @param reward represents the reward accumulated until the claim request
     * @param requestedWithdrawalAt represents the date at which the user requested a withdrawal, used to stop the reward calculations once a request takes place
     * @param withdrawalNFTId represents the NFT Id given at withdrawal request
     * @param noticePeriodId represents the notice period which the user chose to stake for
    */
    struct UserInfo {
        uint256 balance;
        uint256 stakedAt;
        uint256 reward;
        uint256 requestedWithdrawalAt;
        uint256 withdrawalNFTId;
        uint8 noticePeriodId;
    }

    /**
     * @notice RewardTokenInfo struct representing the details of the reward token
     * @param yieldbalance represents the total yield balance of the token
     * @param isWhitelisted represents whether the token is whitelisted or not
    */
    struct RewardTokenInfo {
        uint256 yieldBalance;
        uint256 lastDepositDate;
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
    mapping(address => mapping(address => UserInfo)) public usersMapping; // (tokenAddress => (userAddress => UserInfo))
    mapping(uint8 => NoticePeriodInfo) noticePeriodsMapping;

    uint256 pausedAt;
    WithdrawalNFT public withdrawalNFT;

    /**
     * @notice constructor used to initialize the contract
     * @param _st1wToken is the address of the first notice token (1 week)
     * @param _st4wToken is the address of the second notice token (4 weeks)
     * @param _withdrawalNFTAddress is the address of the withdrawal NFT contract
    */
    constructor(address _st1wToken, address _st4wToken, address _withdrawalNFTAddress) Ownable(msg.sender) {
        adminsMapping[msg.sender] = true;

        noticePeriodsMapping[1].noticePeriod = 1 weeks;
        noticePeriodsMapping[1].withdrawalNoticeToken = _st1wToken;

        noticePeriodsMapping[2].noticePeriod = 4 weeks;
        noticePeriodsMapping[2].withdrawalNoticeToken = _st4wToken;

        withdrawalNFT = WithdrawalNFT(_withdrawalNFTAddress);
    }

    modifier onlyAdmin {
        require(adminsMapping[msg.sender], "User not admin");
        _;
    }

    /**
    * @notice pause allows the owner to pause the contract
    */
    function pause() public onlyOwner {
        _pause();
    }

    /**
    * @notice unpause allows the owner to unpause the contract
    */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
    * @notice setAdmin function modifies the admin status of an address
    * @param _userAddress represents address of that token
    * @param _isAdmin represents the admin status to be set
    */
    function setAdmin(address _userAddress, bool _isAdmin) public onlyOwner {
        adminsMapping[_userAddress] = _isAdmin;
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
        RewardTokenInfo storage rewardToken = rewardTokensMapping[_tokenAddress];
        require(rewardToken.lastDepositDate == 0 || rewardToken.lastDepositDate + 1 weeks <= block.timestamp, "Not enough time passed since last deposit");
        rewardToken.yieldBalance += _amount;
        rewardToken.lastDepositDate = block.timestamp;
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
     * @param _noticePeriodId represents the notice period which the user chose to stake for8u1
    */
    function deposit(address _tokenAddress, uint256 _amount, uint8 _noticePeriodId) public whenNotPaused {
        require(rewardTokensMapping[_tokenAddress].isWhitelisted, "Deposited token not whitelisted");

        UserInfo storage user = usersMapping[_tokenAddress][msg.sender];
        require(user.balance == 0, "User already staking");

        user.balance = _amount;
        user.stakedAt = block.timestamp;
        user.noticePeriodId = _noticePeriodId;

        uint8 tokenDecimals = TemplateERC20(noticePeriodsMapping[_noticePeriodId].withdrawalNoticeToken).decimals();
        IERC20(noticePeriodsMapping[_noticePeriodId].withdrawalNoticeToken).safeTransfer(msg.sender, 1 * 10**tokenDecimals);
        IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @notice getUserReward function calculates the users rewards
     * @param _user represents user to have his rewards calculated
    */
    function getUserReward(UserInfo memory _user) public view returns(uint256) {
        uint256 userCurrentTimestamp = _user.requestedWithdrawalAt;
        if(_user.requestedWithdrawalAt == 0) userCurrentTimestamp = block.timestamp;
        return (_user.balance * (userCurrentTimestamp - _user.stakedAt) * REWARDS_PER_SECOND_NUMERATOR) / REWARDS_PER_SECOND_DENOMINATOR;
    }

    /**
    * @notice requestWithdraw function allows the user to request a withdrawal, it sets the withdrawal date according to the noticeId, and burns the notice token
    * @param _tokenAddress represents address of that token
    */
    function requestWithdraw(address _tokenAddress) public whenNotPaused {
        require(balanceOf(_tokenAddress, msg.sender) > 0, "User did not stake that token");
        UserInfo storage user = usersMapping[_tokenAddress][msg.sender];
        NoticePeriodInfo memory noticePeriodInfo = noticePeriodsMapping[user.noticePeriodId];
        uint8 tokenDecimals = TemplateERC20(noticePeriodInfo.withdrawalNoticeToken).decimals();

        require(IERC20(noticePeriodInfo.withdrawalNoticeToken).balanceOf(msg.sender) >= 1 * 10**tokenDecimals, "User not holding a stake token");

        user.reward = getUserReward(user);
        user.requestedWithdrawalAt = block.timestamp;
        TemplateERC20(noticePeriodInfo.withdrawalNoticeToken).burn(msg.sender, 1 * 10**tokenDecimals);

        uint256 nftId = withdrawalNFT.mintNFT(msg.sender);
        user.withdrawalNFTId = nftId;
    }

    /**
    * @notice isAllowedToClaim function returns whether a date is valid for claim or not yet based on the corresponding notice period
    * @param _requestedWithdrawDate represents the date at which the request was made
    * @param _noticePeriodId represents the ID of the notice period
    */
    function isAllowedToClaim(uint256 _requestedWithdrawDate, uint8 _noticePeriodId) public view returns(bool){
        return _requestedWithdrawDate + noticePeriodsMapping[_noticePeriodId].noticePeriod <= block.timestamp;
    }

    /**
    * @notice claim function makes sure the user's notice period has passed and transfers the earned reward + initially staked tokens and updates the balances
    * @param _tokenAddress represents address of that token
    */
    function claim(address _tokenAddress) public whenNotPaused {
        UserInfo storage user = usersMapping[_tokenAddress][msg.sender];
        require(isAllowedToClaim(user.requestedWithdrawalAt, user.noticePeriodId), "Cannot withdraw yet");
        require(user.reward <= rewardTokensMapping[_tokenAddress].yieldBalance, "Yield balance is not enough, admins must deposit yield");

        rewardTokensMapping[_tokenAddress].yieldBalance -= user.reward;

        uint256 totalToTransfer = user.balance + user.reward;
        user.balance = 0;
        user.reward = 0;
        user.requestedWithdrawalAt = 0;

        uint256 nftId = user.withdrawalNFTId;
        user.withdrawalNFTId = 0;
        withdrawalNFT.burnNFT(nftId);
        IERC20(_tokenAddress).safeTransfer(msg.sender, totalToTransfer);
    }

    /**
    * @notice balanceOf function lets users check the token balance of an address
    * @param _tokenAddress represents address of that token
    * @param _userAddress represents address of that user
    */
    function balanceOf(address _tokenAddress, address _userAddress) public view returns(uint256) {
        return usersMapping[_tokenAddress][_userAddress].balance;
    }

    /**
    * @notice getRewardTokenInfo function returns the RewardTokenInfo struct
    * @param _tokenAddress represents address of that token
    */
    function getRewardTokenInfo(address _tokenAddress) public view returns(RewardTokenInfo memory) {
        return rewardTokensMapping[_tokenAddress];
    }

    /**
    * @notice getUserInfo function returns the UserInfo struct for a specific token
    * @param _tokenAddress represents address of that token
    * @param _userAddress represents address of that user
    */
    function getUserInfo(address _tokenAddress, address _userAddress) public view returns(UserInfo memory) {
        return usersMapping[_tokenAddress][_userAddress];
    }

    /**
    * @notice getNoticeInfo function returns the NoticePeriod struct
    * @param _noticePeriodId represents notice periodId
    */
    function getNoticePeriodInfo(uint8 _noticePeriodId) public view returns(NoticePeriodInfo memory) {
        return noticePeriodsMapping[_noticePeriodId];
    }

    /**
    * @notice isAdmin function returns the admin status of a user
    * @param _userAddress represents address of that user
    */
    function isAdmin(address _userAddress) public view returns(bool) {
        return adminsMapping[_userAddress];
    }
}
