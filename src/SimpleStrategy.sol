// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";

/**
 * @title SimpleStrategy
 * @author Vaultion Team
 * @notice A dummy strategy that simulates yield via a configurable yield factor.
 * This is intended for demonstration or testing purposes.
 */
contract SimpleStrategy is IStrategy {
    /// @notice The asset this strategy manages.
    IERC20 public immutable asset;
    /// @notice The vault that owns this strategy.
    address public immutable vault;
    /// @notice The multiplicative factor to simulate yield (e.g., 1.05e18 for 5% APY).
    uint256 public yieldFactor;

    /**
     * @param _asset The address of the asset to be managed.
     * @param _yieldFactor The simulated yield factor in 1e18 format.
     * @param _vault The address of the parent vault.
     */
    constructor(IERC20 _asset, uint256 _yieldFactor, address _vault) {
        require(_vault != address(0), "SimpleStrategy: Vault address cannot be zero");
        asset = _asset;
        yieldFactor = _yieldFactor;
        vault = _vault;
    }

    /// @dev Throws if called by any account other than the parent vault.
    modifier onlyVault() {
        require(msg.sender == vault, "SimpleStrategy: Caller is not the vault");
        _;
    }

    /**
     * @notice Accepts assets from the vault. For this simulation, no further action is taken.
     * @param amount The amount of assets deposited by the vault.
     */
    function deposit(uint256 amount) external override onlyVault {
        // No additional logic needed for this simple simulation.
    }

    /**
     * @notice Withdraws assets from the strategy back to the vault.
     * @param amount The amount of assets to withdraw.
     */
    function withdraw(uint256 amount) external override onlyVault {
        uint256 balance = asset.balanceOf(address(this));
        uint256 amountToWithdraw = amount > balance ? balance : amount;
        if (amountToWithdraw > 0) {
            asset.transfer(vault, amountToWithdraw);
        }
    }

    /**
     * @notice Returns the total assets held by the strategy, including simulated yield.
     * This is the core of the yield simulation.
     * @return The total value of assets including simulated gains.
     */
    function totalAssets() external view override returns (uint256) {
        uint256 balance = asset.balanceOf(address(this));
        return (balance * yieldFactor) / 1e18;
    }
}
