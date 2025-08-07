// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {BoringVault} from "./BoringVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

/**
 * @title VaultAllocator
 * @author Vaultion Team
 * @notice A smart contract that facilitates seamless reallocation of a user's position
 * between different BoringVaults in a single transaction.
 */
contract VaultAllocator {
    using SafeTransferLib for IERC20;

    /// @notice The administrative address, allowed to register vaults.
    address public admin;
    /// @notice A registry mapping asset tokens to their corresponding vault addresses.
    mapping(address => address) public tokenToVault;

    event VaultRegistered(address indexed token, address indexed vault);
    event Reallocated(
        address indexed user, address indexed fromVault, address indexed toVault, uint256 fromAmount, uint256 toAmount
    );

    constructor() {
        admin = msg.sender;
    }

    /// @dev Throws if called by any account other than the admin.
    modifier onlyAdmin() {
        require(msg.sender == admin, "VaultAllocator: Caller is not the admin");
        _;
    }

    /**
     * @notice Registers a vault for a specific token.
     * @param token The address of the asset token.
     * @param vault The address of the corresponding BoringVault.
     */
    function registerVault(address token, address vault) external onlyAdmin {
        require(token != address(0) && vault != address(0), "VaultAllocator: Zero address provided");
        tokenToVault[token] = vault;
        emit VaultRegistered(token, vault);
    }

    /**
     * @notice Reallocates a user's assets from one vault to another.
     * @param fromToken The asset token of the source vault (e.g., USDC).
     * @param toToken The asset token of the destination vault (e.g., USDT).
     * @param sharesToWithdraw The amount of shares to withdraw from the source vault.
     */
    function reallocate(address fromToken, address toToken, uint256 sharesToWithdraw) external {
        address fromVaultAddr = tokenToVault[fromToken];
        address toVaultAddr = tokenToVault[toToken];
        require(fromVaultAddr != address(0) && toVaultAddr != address(0), "VaultAllocator: Vault not registered");
        require(fromVaultAddr != toVaultAddr, "VaultAllocator: Cannot reallocate to the same vault");

        BoringVault fromVault = BoringVault(fromVaultAddr);
        uint256 totalAssetsFromVault = fromVault.totalAssets();
        uint256 totalSharesFromVault = fromVault.totalShares();
        uint256 fromAmount = (sharesToWithdraw * totalAssetsFromVault) / totalSharesFromVault;

        fromVault.withdrawForReallocation(msg.sender, sharesToWithdraw, address(this));

        uint256 toAmount = _swap(toToken, fromAmount);

        IERC20(toToken).approve(toVaultAddr, toAmount);
        BoringVault(toVaultAddr).deposit(toAmount, msg.sender);

        emit Reallocated(msg.sender, fromVaultAddr, toVaultAddr, fromAmount, toAmount);
    }

    /**
     * @dev Internal function to simulate a token swap. For this version, it assumes a 1:1 rate
     * and relies on the contract being pre-funded with liquidity.
     * @param toToken The token to be received from the swap.
     * @param amountIn The amount of the input token.
     * @return amountOut The amount of the output token.
     */
    function _swap(address toToken, uint256 amountIn) internal view returns (uint256 amountOut) {
        require(IERC20(toToken).balanceOf(address(this)) >= amountIn, "VaultAllocator: Insufficient liquidity for swap");
        return amountIn; // Assume 1:1 rate for hackathon
    }
}
