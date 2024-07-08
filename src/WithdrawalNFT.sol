// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WithdrawalNFT is ERC721, Ownable {
    uint256 private _tokenIds;

    constructor() ERC721("WithdrawalNFT", "WNFT") Ownable(msg.sender){}

    function mintNFT(address recipient) external onlyOwner returns (uint256) {
        _tokenIds += 1;
        uint256 newItemId = _tokenIds;
        _mint(recipient, newItemId);
        return newItemId;
    }

    function burnNFT(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
    }
}