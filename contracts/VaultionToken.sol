// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VaultionToken
 * @author Vaultion Team
 * @notice The native ERC20 token for the Vaultion protocol, used for rewards.
 */
contract VaultionToken is ERC20, Ownable {
    /// @notice The initial total supply of VLTN tokens.
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;

    constructor() ERC20("Vaultion", "VLTN") Ownable(msg.sender) {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    /**
     * @notice Allows the owner to mint additional tokens.
     * @param to The address to receive the new tokens.
     * @param amount The amount of new tokens to mint.
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Allows any user to burn their own tokens.
     * @param amount The amount of tokens to burn from the caller's balance.
     */
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
}