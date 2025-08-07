// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BoringVault} from "./BoringVault.sol";

/**
 * @title RewardManager
 * @author Vaultion Team
 * @notice Manages the distribution of reward tokens to users staking in various vaults.
 * Uses a fair reward accumulator pattern to prevent exploitation.
 */
contract RewardManager {
    /// @notice The reward token (VLTN) to be distributed.
    IERC20 public immutable rewardToken;
    /// @notice The administrative address.
    address public admin;

    /// @notice Stores the unclaimed rewards for each user per vault.
    mapping(address => mapping(address => uint256)) public rewards;
    /// @notice The global accumulator: total rewards distributed per single share in a vault.
    mapping(address => uint256) public rewardPerTokenStored;
    /// @notice Tracks the accumulator value last paid out to a user.
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;
    /// @notice Tracks the timestamp when the global accumulator was last updated for a vault.
    mapping(address => uint256) public lastUpdateTime;
    /// @notice The rate of reward distribution per second for each vault.
    mapping(address => uint256) public rewardRatePerSecond;

    event RewardClaimed(address indexed vault, address indexed user, uint256 amount);
    event RewardRateUpdated(address indexed vault, uint256 newRate);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);
    event UnusedRewardWithdrawn(address indexed to, uint256 amount);

    /// @dev Throws if called by any account other than the admin.
    modifier onlyAdmin() {
        require(msg.sender == admin, "RewardManager: Caller is not the admin");
        _;
    }

    /// @dev Modifier to update a vault's reward accumulator before a state change.
    modifier updateRewardForVault(address vault) {
        rewardPerTokenStored[vault] = rewardPerToken(vault);
        lastUpdateTime[vault] = block.timestamp;
        _;
    }

    constructor(IERC20 _rewardToken) {
        rewardToken = _rewardToken;
        admin = msg.sender;
    }

    /**
     * @notice Calculates the current reward-per-token accumulator value for a vault.
     * @param vault The address of the vault.
     * @return The up-to-date reward per token value.
     */
    function rewardPerToken(address vault) public view returns (uint256) {
        uint256 totalShares = BoringVault(vault).totalShares();
        if (totalShares == 0) {
            return rewardPerTokenStored[vault];
        }
        uint256 timeDiff = block.timestamp - lastUpdateTime[vault];
        return rewardPerTokenStored[vault] + (timeDiff * rewardRatePerSecond[vault] * 1e18) / totalShares;
    }

    /**
     * @notice View function to check the pending rewards for a user in a specific vault.
     * @param vault The address of the vault.
     * @param user The address of the user.
     * @return The amount of pending reward tokens.
     */
    function pendingReward(address vault, address user) external view returns (uint256) {
        return _getPendingReward(vault, user);
    }

    /**
     * @notice Allows a user to claim their accumulated rewards from a vault.
     * @param vault The address of the vault from which to claim rewards.
     */
    function claimReward(address vault) external {
        updateReward(vault, msg.sender);
        uint256 reward = rewards[vault][msg.sender];
        if (reward > 0) {
            rewards[vault][msg.sender] = 0;
            rewardToken.transfer(msg.sender, reward);
            emit RewardClaimed(vault, msg.sender, reward);
        }
    }

    /**
     * @notice A hook called by the vault to update a user's reward state before their share balance changes.
     * @param vault The address of the vault.
     * @param user The address of the user to update.
     */
    function updateReward(address vault, address user) public updateRewardForVault(vault) {
        rewards[vault][user] = _getPendingReward(vault, user);
        userRewardPerTokenPaid[vault][user] = rewardPerTokenStored[vault];
    }

    /**
     * @dev Internal function containing the core logic for calculating a user's pending rewards.
     */
    function _getPendingReward(address vault, address user) internal view returns (uint256) {
        uint256 userShares = BoringVault(vault).getUserShares(user);
        uint256 rpt = rewardPerToken(vault);
        uint256 userRewardPerToken = (userShares * (rpt - userRewardPerTokenPaid[vault][user])) / 1e18;
        return rewards[vault][user] + userRewardPerToken;
    }

    //- ADMIN FUNCTIONS -//

    /**
     * @notice Sets the reward distribution rate for a vault.
     * @param vault The address of the vault.
     * @param rate The new reward rate in tokens per second (with 18 decimals).
     */
    function setRewardRate(address vault, uint256 rate) external onlyAdmin updateRewardForVault(vault) {
        rewardRatePerSecond[vault] = rate;
        emit RewardRateUpdated(vault, rate);
    }

    /**
     * @notice Updates the administrative address.
     * @param newAdmin The address of the new admin.
     */
    function setAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "RewardManager: New admin cannot be zero address");
        emit AdminChanged(admin, newAdmin);
        admin = newAdmin;
    }

    /**
     * @notice Allows the admin to withdraw unused reward tokens from the contract.
     * @param to The address to receive the tokens.
     * @param amount The amount of tokens to withdraw.
     */
    function withdrawUnusedReward(address to, uint256 amount) external onlyAdmin {
        require(to != address(0), "RewardManager: Cannot withdraw to zero address");
        rewardToken.transfer(to, amount);
        emit UnusedRewardWithdrawn(to, amount);
    }
}
