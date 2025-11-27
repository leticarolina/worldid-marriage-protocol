// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20, ERC20Burnable} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title DayToken
 * @dev A basic ERC20 token used for rewarding bonded users.
 */
contract TimeToken is ERC20, ERC20Burnable, Ownable {
    constructor() ERC20("TIME", "TIME") Ownable(msg.sender) {}

    /// @notice Mint new DAY tokens to a specified address.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
