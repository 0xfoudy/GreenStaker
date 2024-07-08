// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TemplateERC20} from "../src/TemplateERC20.sol";
import {GreenStaker} from "../src/GreenStaker.sol";
import {WithdrawalNFT} from "../src/WithdrawalNFT.sol";

contract GreenStakerTest is Test {
    using SafeERC20 for IERC20;

    uint256 public constant TOTAL_SUPPLY = 150_000_000_000 * 10**18;
    uint8 public constant FIRST_NOTICE_ID = 1;
    uint8 public constant SECOND_NOTICE_ID = 2;
    address user1 = address(1);
    address user2 = address(2);
    address user3 = address(3);
    address user4 = address(4);
    
    TemplateERC20 allowedToken1;
    TemplateERC20 allowedToken2;
    TemplateERC20 unallowedToken1;
    TemplateERC20 st1wERC20;
    TemplateERC20 st4wERC20;

    GreenStaker public stakerContract;
    WithdrawalNFT public NFTContract;

    function setUp() public {
        // create the tokens
        allowedToken1 = new TemplateERC20(TOTAL_SUPPLY, "Token1", "TKN1");
        allowedToken2 = new TemplateERC20(TOTAL_SUPPLY, "Token2", "TKN2");
        unallowedToken1 = new TemplateERC20(TOTAL_SUPPLY, "Token3", "TKN3");
        st1wERC20 = new TemplateERC20(TOTAL_SUPPLY, "st1wERC20", "st1w");
        st4wERC20 = new TemplateERC20(TOTAL_SUPPLY, "st4wERC20", "st4w");
        NFTContract = new WithdrawalNFT();
        // create the smart contract
        stakerContract = new GreenStaker(address(st1wERC20), address(st4wERC20), address(NFTContract));
        NFTContract.transferOwnership(address(stakerContract));
    }

    /**
    * @notice test_setTokenWhitelist function makes sure only the owner can set a token as whitelisted
    */
    function test_setTokenWhitelist() public {
        address addressToken1 = address(allowedToken1);
        vm.prank(user1);
        vm.expectRevert();
        stakerContract.setTokenWhitelist(addressToken1, true);
        stakerContract.setTokenWhitelist(addressToken1, true);
        
        assertTrue(stakerContract.getRewardTokenInfo(addressToken1).isWhitelisted);
        assertFalse(stakerContract.getRewardTokenInfo(address(allowedToken2)).isWhitelisted);
    }

    /**
    * @notice test_setAdmin function makes sure only the owner can set an address as admin
    */
    function test_setAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        stakerContract.setAdmin(user1, true);
        assertFalse(stakerContract.isAdmin(user1));
        stakerContract.setAdmin(user1, true);
        assertTrue(stakerContract.isAdmin(user1));
    }

    /**
    * @notice test_adminYieldDeposit function makes sure only the admin can deposit yield tokens weekly and that the balance is updated
    */
    function test_adminYieldDeposit() public {
        address token1Address = address(allowedToken1);
        deal(token1Address, user1, 100_000_000 * 10**18);
        vm.startPrank(user1);
        allowedToken1.approve(address(stakerContract), type(uint256).max);
        vm.expectRevert("User not admin");
        stakerContract.adminYieldDeposit(token1Address, 50_000_000 * 10**18);
        vm.stopPrank();

        stakerContract.setAdmin(user1, true);
        vm.startPrank(user1);
        stakerContract.adminYieldDeposit(token1Address, 50_000_000 * 10**18);
        vm.expectRevert("Not enough time passed since last deposit");
        stakerContract.adminYieldDeposit(token1Address, 50_000_000 * 10**18);

        vm.assertEq(stakerContract.getRewardTokenInfo(token1Address).yieldBalance, 50_000_000 * 10**18);
        vm.warp(block.timestamp + 1 weeks);
        stakerContract.adminYieldDeposit(token1Address, 50_000_000 * 10**18);
        vm.assertEq(stakerContract.getRewardTokenInfo(token1Address).yieldBalance, 100_000_000 * 10**18);
    }

    /**
    * @notice test_deposit function makes sure the user can deposit once , updates the user's info and transfers the staked tokens from the user and the notice token to the user
    */
    function test_deposit() public {
        address token1Address = address(allowedToken1);
        uint256 amountToDeal = 100_000_000 * 10**18;
        uint256 amountToDeposit = 50_000_000 * 10**18;

        deal(token1Address, user1, amountToDeal);
        deal(address(st1wERC20), address(stakerContract), amountToDeal);
        deal(address(st4wERC20), address(stakerContract), amountToDeal);

        // test fail on pause
        stakerContract.pause();
        vm.expectRevert();
        stakerContract.deposit(token1Address, amountToDeposit, FIRST_NOTICE_ID);
        stakerContract.unpause();

        vm.startPrank(user1);
        allowedToken1.approve(address(stakerContract), type(uint256).max);

        vm.expectRevert("Deposited token not whitelisted");
        stakerContract.deposit(token1Address, amountToDeposit, FIRST_NOTICE_ID);
        vm.stopPrank();
        test_setTokenWhitelist();
        vm.assertEq(allowedToken1.balanceOf(user1), amountToDeal);

        vm.startPrank(user1);
        stakerContract.deposit(token1Address, amountToDeposit, FIRST_NOTICE_ID);
        
        // Make sure UserInfo is updated
        GreenStaker.UserInfo memory userInfo = stakerContract.getUserInfo(token1Address, user1);
        vm.assertEq(userInfo.balance, amountToDeposit);
        vm.assertEq(userInfo.noticePeriodId, FIRST_NOTICE_ID);
        vm.assertEq(userInfo.stakedAt, block.timestamp);

        // Make sure balances are updated
        vm.assertEq(allowedToken1.balanceOf(user1), amountToDeal - amountToDeposit);
        vm.assertEq(allowedToken1.balanceOf(address(stakerContract)), amountToDeal - amountToDeposit);
        vm.assertEq(st1wERC20.balanceOf(user1), 1 * 10**18);

        // User cannot re stake the same token
        vm.expectRevert("User already staking");
        stakerContract.deposit(token1Address, amountToDeposit, SECOND_NOTICE_ID);
        vm.stopPrank();
    }

    /**
    * @notice test_postDeposit function checks that the user is able to handle the received stake tokens like any other ERC20 and that balanceOf works
    */
    function test_postDeposit() public {
        test_deposit();
        vm.assertEq(st1wERC20.balanceOf(user1), 10**18);
        vm.assertEq(st1wERC20.balanceOf(user2), 0);

        vm.prank(user1);
        IERC20(address(st1wERC20)).safeTransfer(user2, 10**18);

        vm.assertEq(st1wERC20.balanceOf(user1), 0);
        vm.assertEq(st1wERC20.balanceOf(user2), 10**18);
        uint256 amountToDeposit = 50_000_000 * 10**18;
        vm.assertEq(stakerContract.balanceOf(address(allowedToken1), user1), amountToDeposit);
    }

    /**
    * @notice test_requestWithdraw function checks that the user is able to request a withdraw and upon that, have the stake token burned and withdrawal Date and reward updated
    */
    function test_requestWithdraw() public {
        test_deposit();
        address token1Address = address(allowedToken1);

        // test fail on pause
        stakerContract.pause();
        vm.expectRevert();
        stakerContract.requestWithdraw(token1Address);
        stakerContract.unpause();
        
        // cannot request withdraw without holding the stake token
        vm.startPrank(user1);
        IERC20(address(st1wERC20)).safeTransfer(user2, 10**18);
        vm.expectRevert("User not holding a stake token");
        stakerContract.requestWithdraw(token1Address);
        vm.stopPrank();

        // cannot request withdraw without having staked tokens despite having a stake token(st1w)
        vm.startPrank(user2);
        vm.expectRevert();
        stakerContract.requestWithdraw(token1Address); // will revert without error because user has no mapping
        IERC20(address(st1wERC20)).safeTransfer(user1, 10**18);
        vm.stopPrank();

        vm.startPrank(user1);

        vm.expectRevert("User did not stake that token");
        stakerContract.requestWithdraw(address(allowedToken2));

        uint256 st1wSupply = IERC20(address(st1wERC20)).totalSupply();
        stakerContract.requestWithdraw(token1Address);
        vm.stopPrank();

        assertEq(IERC20(address(st1wERC20)).balanceOf(user1), 0);
        assertEq(IERC20(address(st1wERC20)).totalSupply(), st1wSupply - 1 * 10**18);
        
        // make sure the NFT was minted
        assertEq(NFTContract.ownerOf(1), user1);

        GreenStaker.UserInfo memory user = stakerContract.getUserInfo(address(allowedToken1), user1);
        assertEq(user.requestedWithdrawalAt, block.timestamp);
        assertFalse(stakerContract.isAllowedToClaim(user.requestedWithdrawalAt, user.noticePeriodId));
        vm.warp(block.timestamp + stakerContract.getNoticePeriodInfo(user.noticePeriodId).noticePeriod);
        assertTrue(stakerContract.isAllowedToClaim(user.requestedWithdrawalAt, user.noticePeriodId));
    }

    /**
    * @notice test_rewardCalculate function checks that the user's reward is calculated and it stops adding as soon as a withdrawal is requested
    */
    function test_rewardCalculation() public {
        vm.warp(1);
        test_deposit();
        vm.warp(15_778_800 + 1); // half a year leap
        vm.prank(user1);
        stakerContract.requestWithdraw(address(allowedToken1));
        GreenStaker.UserInfo memory user = stakerContract.getUserInfo(address(allowedToken1), user1);
        uint256 userCurrentReward = user.reward;

        assertTrue(userCurrentReward > user.balance * 5 / 200 - 10**15); // interest should be at 2.5%, precision loss of 0.5 at (10 ** 15)
        
        vm.warp(52 weeks); // 1 year leap, make sure the reward stays and isn't doubled or changed due to a withdrawal request already taking place
        assertEq(stakerContract.getUserReward(user), userCurrentReward);
    }

    /**
    * @notice test_claim function checks that the user can claim his tokens and rewards and that balances are updated properly
    */
    function test_claim() public {
        vm.warp(1);
        test_deposit();
        vm.warp(15_778_800 + 1); // half a year leap
        vm.startPrank(user1);

        address token1Address = address(allowedToken1);
        stakerContract.requestWithdraw(token1Address);
        GreenStaker.UserInfo memory user = stakerContract.getUserInfo(token1Address, user1);

        uint256 userEarnedReward = user.reward;
        uint256 userStakedBalance = user.balance;
        uint256 userTokenBalance = allowedToken1.balanceOf(user1);

        vm.expectRevert("Cannot withdraw yet");
        stakerContract.claim(token1Address);
        vm.warp(15_778_800 + 1 weeks + 1); // due to 1 week notice
        vm.expectRevert("Yield balance is not enough, admins must deposit yield");
        stakerContract.claim(token1Address);
        vm.stopPrank();

        allowedToken1.approve(address(stakerContract), type(uint256).max);
        stakerContract.adminYieldDeposit(token1Address, 100_000_000 * 10**18);

        // make sure the NFT existed
        assertEq(NFTContract.ownerOf(1), user1);

        // test fail on pause
        stakerContract.pause();
        vm.expectRevert();
        stakerContract.claim(token1Address);
        stakerContract.unpause();
        
        vm.prank(user1);
        stakerContract.claim(token1Address);

        // make sure the NFT existed
        vm.expectRevert();
        NFTContract.ownerOf(1);

        user = stakerContract.getUserInfo(token1Address, user1);
        assertEq(user.reward, 0);
        assertEq(user.balance, 0);
        assertEq(allowedToken1.balanceOf(user1), userTokenBalance + userEarnedReward + userStakedBalance);
    }

    function test_modifyNoticePeriod() public {
        test_requestWithdraw();
        GreenStaker.UserInfo memory user = stakerContract.getUserInfo(address(allowedToken1), user1);
        assertTrue(stakerContract.isAllowedToClaim(user.requestedWithdrawalAt, user.noticePeriodId));

        stakerContract.adminModifyNoticePeriod(user.noticePeriodId, 8 weeks);
        assertFalse(stakerContract.isAllowedToClaim(user.requestedWithdrawalAt, user.noticePeriodId));
        vm.warp(block.timestamp + 8 weeks);
        assertTrue(stakerContract.isAllowedToClaim(user.requestedWithdrawalAt, user.noticePeriodId));
    }
}