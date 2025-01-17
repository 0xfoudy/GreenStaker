// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TemplateERC20 is ERC20 {
    constructor(uint256 _initialSupply, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        _mint(msg.sender, _initialSupply);
    }

    function burn(address _address, uint256 amount) public {
        _burn(_address, amount);
    }
}
