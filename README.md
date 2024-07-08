# GreenStaker

## Project is built with Foundry

https://book.getfoundry.sh/

## Assumptions
1. The reward is the same token as the staked one. (If a user stakes token A, the token A will be given as reward)
2. Users cannot stake again as long as they didn't claim
3. All notice periods falls under the same pool as they all share the same yield interest of 5%
4. The given stxw ERC20 tokens do not grant the right to request a withdrawal (If user A transfered his st1w token to user B, user B cannot claim the tokens of user A)
5. Rewards are not calculated during the paused period


## TO DO
1. Write tests X
2. Allow users to stake more than 1 token X 
3. Pause / Unpause feature
4. claim NFT
5. test admin modifying claim periods