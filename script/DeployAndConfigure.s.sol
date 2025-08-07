// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// ... (semua import tetap sama) ...
import {VaultionToken} from "../contracts/VaultionToken.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {BoringVault} from "../src/BoringVault.sol";
import {RewardManager} from "../src/RewardManager.sol";
import {SimpleStrategy} from "../src/SimpleStrategy.sol";
import {VaultAllocator} from "../src/VaultAllocator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract DeployAndConfigure is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // --- Langkah 1: Deploy & Mint Semua Token ---
        console.log("Deploying Tokens...");
        VaultionToken vltn = new VaultionToken();
        MockERC20 usdc = new MockERC20("Mock USDC", "USDC");
        MockERC20 usdt = new MockERC20("Mock USDT", "USDT");

        // --- LANGKAH TAMBAHAN: MINT MOCK TOKENS ---
        console.log("Minting mock tokens to deployer...");
        // Mint 10 Juta USDC dan USDT ke alamat deployer
        usdc.mint(deployer, 10_000_000 * 1e18);
        usdt.mint(deployer, 10_000_000 * 1e18);

        // --- Langkah 2, 3, 4 (tetap sama) ---
        console.log("Deploying Core Contracts...");
        RewardManager rewardManager = new RewardManager(IERC20(address(vltn)));
        BoringVault vaultUSDC = new BoringVault(deployer, ERC20(address(usdc)));
        BoringVault vaultUSDT = new BoringVault(deployer, ERC20(address(usdt)));
        BoringVault vaultVLTN = new BoringVault(deployer, ERC20(address(vltn)));

        console.log("Deploying Strategies...");
        SimpleStrategy strategyUSDC = new SimpleStrategy(IERC20(address(usdc)), 1.05e18, address(vaultUSDC));
        SimpleStrategy strategyUSDT = new SimpleStrategy(IERC20(address(usdt)), 1.04e18, address(vaultUSDT));

        console.log("Deploying Vault Allocator...");
        VaultAllocator allocator = new VaultAllocator();
        console.log("VaultAllocator deployed at:", address(allocator));

        // --- Langkah 5: Konfigurasi & Hubungkan Semuanya (tetap sama) ---
        console.log("\nConfiguring and Connecting Contracts...");

        // 5a. Hubungkan Vault ke Strategi & Reward Manager
        console.log("Setting strategies and reward manager for vaults...");
        vaultUSDC.setStrategy(strategyUSDC);
        vaultUSDT.setStrategy(strategyUSDT);
        vaultUSDC.setRewardManager(address(rewardManager));
        vaultUSDT.setRewardManager(address(rewardManager));
        vaultVLTN.setRewardManager(address(rewardManager));

        // 5b. Atur Reward Rates
        console.log("Setting reward rates in RewardManager...");
        rewardManager.setRewardRate(address(vaultUSDC), 0.1e18);
        rewardManager.setRewardRate(address(vaultUSDT), 0.08e18);
        rewardManager.setRewardRate(address(vaultVLTN), 0.05e18);

        // 5c. Daftarkan Vaults ke dalam Allocator
        console.log("Registering vaults in VaultAllocator...");
        allocator.registerVault(address(usdc), address(vaultUSDC));
        allocator.registerVault(address(usdt), address(vaultUSDT));

        // LANGKAH TAMBAHAN: Atur Allocator di setiap Vault
        console.log("Setting allocator address in vaults...");
        vaultUSDC.setAllocator(address(allocator));
        vaultUSDT.setAllocator(address(allocator));

        // 5d. Kirim Dana (Modal) ke Kontrak Inti
        console.log("Funding contracts...");
        // Kirim 1 Juta VLTN ke RewardManager untuk hadiah
        vltn.transfer(address(rewardManager), 1_000_000 * 1e18);

        // Kirim 1 Juta USDC & USDT ke Allocator untuk likuiditas swap simulasi
        usdc.transfer(address(allocator), 1_000_000 * 1e18);
        usdt.transfer(address(allocator), 1_000_000 * 1e18);

        console.log("\n Deployment and final configuration complete!");
        vm.stopBroadcast();
    }
}
