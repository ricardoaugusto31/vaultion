// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {IRewardManager} from "./interfaces/IRewardManager.sol";

/**
 * @title BoringVault
 * @author Vaultion Team
 * @notice A simple yield-bearing vault that accepts a single asset,
 * deposits it into a strategy, and distributes shares to users.
 * It integrates with a RewardManager for distributing separate reward tokens.
 */
contract BoringVault is Auth {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    //- STATE -//

    /// @notice The underlying asset this vault holds.
    ERC20 public immutable asset;
    /// @notice The yield-generating strategy contract.
    IStrategy public strategy;
    /// @notice The contract responsible for calculating and distributing rewards.
    address public rewardManager;
    /// @notice The contract authorized to perform reallocations on behalf of users.
    address public allocator;

    /// @notice Mapping of user addresses to their share balances.
    mapping(address => uint256) public userShares;
    /// @notice The total amount of shares issued by the vault.
    uint256 public totalShares;

    //- EVENTS -//

    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 amount, uint256 shares);
    event StrategyUpdated(address indexed newStrategy);
    event RewardManagerUpdated(address indexed newManager);
    event AllocatorUpdated(address indexed newAllocator);

    constructor(address _owner, ERC20 _asset) Auth(_owner, Authority(address(0))) {
        asset = _asset;
    }

    //- ADMIN FUNCTIONS -//

    /**
     * @notice Sets or updates the strategy for the vault.
     * @param _strategy The address of the new strategy contract.
     */
    function setStrategy(IStrategy _strategy) external requiresAuth {
        require(address(_strategy) != address(0), "BoringVault: Invalid strategy address");
        strategy = _strategy;
        emit StrategyUpdated(address(_strategy));
    }

    /**
     * @notice Sets the RewardManager contract address.
     * @param _manager The address of the RewardManager contract.
     */
    function setRewardManager(address _manager) external requiresAuth {
        rewardManager = _manager;
        emit RewardManagerUpdated(_manager);
    }

    /**
     * @notice Sets the trusted VaultAllocator contract address.
     * @param _allocator The address of the VaultAllocator contract.
     */
    function setAllocator(address _allocator) external requiresAuth {
        allocator = _allocator;
        emit AllocatorUpdated(_allocator);
    }

    /**
     * @notice Allows the owner to withdraw funds directly from the strategy in an emergency.
     * @param amount The amount of the asset to withdraw from the strategy.
     */
    function emergencyWithdraw(uint256 amount) external requiresAuth {
        strategy.withdraw(amount);
        asset.safeTransfer(msg.sender, amount);
    }

    //- USER FUNCTIONS -//

    /**
     * @notice Deposits assets into the vault and mints shares for the receiver.
     * @param amount The amount of the asset to deposit.
     * @param receiver The address that will receive the vault shares.
     */
    function deposit(uint256 amount, address receiver) external {
        require(amount > 0, "BoringVault: Amount must be > 0");
        require(receiver != address(0), "BoringVault: Receiver cannot be zero address");

        if (rewardManager != address(0)) {
            IRewardManager(rewardManager).updateReward(address(this), receiver);
        }

        uint256 totalAssetsBefore = totalAssets();
        asset.safeTransferFrom(msg.sender, address(this), amount);

        uint256 shares = totalShares == 0 ? amount : amount.mulDivDown(totalShares, totalAssetsBefore);

        userShares[receiver] += shares;
        totalShares += shares;

        if (address(strategy) != address(0)) {
            asset.safeApprove(address(strategy), amount);
            strategy.deposit(amount);
        }
        emit Deposit(receiver, amount, shares);
    }

    /**
     * @notice Withdraws assets by burning shares.
     * @dev Assets are withdrawn from the caller's share balance but sent to the specified receiver.
     * @param shares The amount of shares to burn.
     * @param receiver The address that will receive the withdrawn assets.
     */
    function withdraw(uint256 shares, address receiver) external {
        require(shares > 0, "BoringVault: Shares must be > 0");
        require(receiver != address(0), "BoringVault: Receiver cannot be zero address");
        require(userShares[msg.sender] >= shares, "BoringVault: Insufficient shares");

        if (rewardManager != address(0)) {
            IRewardManager(rewardManager).updateReward(address(this), msg.sender);
        }

        uint256 amount = shares.mulDivDown(totalAssets(), totalShares);

        userShares[msg.sender] -= shares;
        totalShares -= shares;

        if (address(strategy) != address(0)) {
            uint256 vaultBalance = asset.balanceOf(address(this));
            if (amount > vaultBalance) {
                strategy.withdraw(amount - vaultBalance);
            }
        }

        asset.safeTransfer(receiver, amount);
        emit Withdraw(msg.sender, amount, shares);
    }

    //- ALLOCATOR FUNCTION -//

    /**
     * @notice Withdraws assets on behalf of a user for reallocation.
     * @dev Can only be called by the registered VaultAllocator contract.
     * @param user The user whose shares are being withdrawn.
     * @param shares The amount of shares to burn.
     * @param receiver The address to send the withdrawn assets to (typically the VaultAllocator).
     */
    function withdrawForReallocation(address user, uint256 shares, address receiver) external {
        require(msg.sender == allocator, "BoringVault: Caller is not the registered allocator");
        require(shares > 0, "BoringVault: Shares must be > 0");
        require(userShares[user] >= shares, "BoringVault: Insufficient shares for user");

        if (rewardManager != address(0)) {
            IRewardManager(rewardManager).updateReward(address(this), user);
        }

        uint256 amount = shares.mulDivDown(totalAssets(), totalShares);

        userShares[user] -= shares;
        totalShares -= shares;

        if (address(strategy) != address(0)) {
            uint256 vaultBalance = asset.balanceOf(address(this));
            if (amount > vaultBalance) {
                strategy.withdraw(amount - vaultBalance);
            }
        }

        asset.safeTransfer(receiver, amount);
        emit Withdraw(user, amount, shares);
    }

    //- VIEW FUNCTIONS -//

    /**
     * @notice Calculates the total amount of assets under management in the vault and its strategy.
     * @return The total value of assets.
     */
    function totalAssets() public view returns (uint256) {
        if (address(strategy) == address(0)) {
            return asset.balanceOf(address(this));
        }
        return asset.balanceOf(address(this)) + strategy.totalAssets();
    }

    /**
     * @notice Retrieves the share balance of a specific user.
     * @param user The address of the user.
     * @return The user's share balance.
     */
    function getUserShares(address user) external view returns (uint256) {
        return userShares[user];
    }
}
