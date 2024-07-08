# GreenStaker

## Project is built with Foundry

https://book.getfoundry.sh/

## Assumptions
1. The reward is the same token as the staked one. (If a user stakes token A, the token A will be given as reward)
2. Users cannot stake again as long as they didn't claim
3. All notice periods falls under the same pool as they all share the same yield interest of 5%
4. The given stxw ERC20 tokens do not grant the right to request a withdrawal (If user A transfered his st1w token to user B, user B cannot claim the tokens of user A)


## Remarks
1. Add events
2. Use access control if there's more than 1 Role
3. Let pause stop reward calculation
4. Grant NFT instead of ERC20 to transfer stake ownership along with the stake token => liquid stake
5. Coverage report (Forge coverage) at 93.75%, 1 branch left to cover
6. Clean slither report
