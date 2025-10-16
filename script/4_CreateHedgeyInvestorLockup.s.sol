// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./BaseScript.sol";
import "./ConfigLoader.sol";

/**
 * @title CreateHedgeyInvestorLockup
 * @notice Calls Hedgey's InvestorLockup contract `createPlan` on Linea networks.
 * @dev Uses a typed interface for `createPlan` and takes parameters from env
 *      variables to avoid raw calldata in configuration.
 *
 * Usage:
 *   # Default (dev)
 *   forge script script/4_CreateHedgeyInvestorLockup.s.sol:CreateHedgeyInvestorLockup \
 *     --rpc-url linea_sepolia \
 *     --broadcast
 *
 *   # Explicit non-default environment via ENV
 *   ENV=production forge script script/4_CreateHedgeyInvestorLockup.s.sol:CreateHedgeyInvestorLockup \
 *     --rpc-url linea \
 *     --broadcast
 *
 * Environment Variables:
 *   - PRIVATE_KEY: Deployer key for broadcasting
 *   - ENV: Select public config JSON
 *   - Optional overrides (only if not set in config):
 *       HEDGEY_INVESTOR_LOCKUP, HEDGEY_BATCH_PLANNER,
 *       HEDGEY_RECIPIENT, HEDGEY_AMOUNT, HEDGEY_START,
 *       HEDGEY_CLIFF, HEDGEY_RATE, HEDGEY_PERIOD,
 *       CNS_TOKEN_L2_PROXY
 *
 * Notes:
 *   - Configure the parameters above in your `.env` or export them in shell.
 */
interface IInvestorLockup {
    function createPlan(
        address recipient,
        address token,
        uint256 amount,
        uint256 start,
        uint256 cliff,
        uint256 rate,
        uint256 period
    ) external returns (uint256 newPlanId);
    function balanceOf(address owner) external view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function plans(uint256 planId)
        external
        view
        returns (address token, uint256 amount, uint256 start, uint256 cliff, uint256 rate, uint256 period);
}

interface IERC20Minimal {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface ICNSAllowlistViews {
    function isSenderAllowlisted(address account) external view returns (bool);
    function senderAllowlistEnabled() external view returns (bool);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function paused() external view returns (bool);
}

interface ICNSAllowlistAdmin {
    function setSenderAllowed(address account, bool allowed) external;
}

struct Plan {
    address recipient;
    uint256 amount;
    uint256 start;
    uint256 cliff;
    uint256 rate;
}

interface IHedgeyBatchPlanner {
    function batchLockingPlans(
        address locker,
        address token,
        uint256 totalAmount,
        Plan[] calldata plans,
        uint256 period,
        uint8 mintType
    ) external;
}

contract CreateHedgeyInvestorLockup is BaseScript {
    address public hedgeyInvestorLockup;
    address public hedgeyBatchPlanner;

    function run() external {
        EnvConfig memory cfg = _loadEnvConfig();
        (uint256 deployerPrivateKey, address deployer) = _getDeployer();

        // Load and validate target contract addresses (prefer config, fallback env)
        hedgeyInvestorLockup = cfg.hedgey.investorLockup;
        if (hedgeyInvestorLockup == address(0)) {
            hedgeyInvestorLockup = vm.envAddress("HEDGEY_INVESTOR_LOCKUP");
        }
        _requireNonZeroAddress(hedgeyInvestorLockup, "HEDGEY_INVESTOR_LOCKUP");
        _requireContract(hedgeyInvestorLockup, "HEDGEY_INVESTOR_LOCKUP");

        hedgeyBatchPlanner = cfg.hedgey.batchPlanner;
        if (hedgeyBatchPlanner == address(0)) {
            hedgeyBatchPlanner = vm.envAddress("HEDGEY_BATCH_PLANNER");
        }
        _requireNonZeroAddress(hedgeyBatchPlanner, "HEDGEY_BATCH_PLANNER");
        _requireContract(hedgeyBatchPlanner, "HEDGEY_BATCH_PLANNER");

        // Load parameters (prefer config, fallback env)
        address recipient = cfg.hedgey.recipient;
        if (recipient == address(0)) {
            recipient = vm.envAddress("HEDGEY_RECIPIENT");
        }
        address token = cfg.l2.proxy;
        if (token == address(0)) {
            // fallback: env variable or broadcast inference used in other scripts
            try vm.envAddress("CNS_TOKEN_L2_PROXY") returns (address a) {
                token = a;
            } catch {
                token = _inferL2ProxyFromBroadcast(block.chainid);
            }
        }
        uint256 amount = cfg.hedgey.amount != 0 ? cfg.hedgey.amount : vm.envUint("HEDGEY_AMOUNT");
        uint256 start = cfg.hedgey.start != 0 ? cfg.hedgey.start : vm.envUint("HEDGEY_START");
        uint256 cliff = cfg.hedgey.cliff != 0 ? cfg.hedgey.cliff : vm.envUint("HEDGEY_CLIFF");
        uint256 rate = cfg.hedgey.rate != 0 ? cfg.hedgey.rate : vm.envUint("HEDGEY_RATE");
        uint256 period = cfg.hedgey.period != 0 ? cfg.hedgey.period : vm.envUint("HEDGEY_PERIOD");

        _requireNonZeroAddress(recipient, "HEDGEY_RECIPIENT");
        _requireNonZeroAddress(token, "CNS_TOKEN_L2_PROXY");
        require(amount > 0, "HEDGEY_AMOUNT must be > 0");
        require(period > 0, "HEDGEY_PERIOD must be > 0");
        require(rate > 0, "HEDGEY_RATE must be > 0");
        require(start <= cliff, "start must be <= cliff");

        // Log context
        _logDeploymentHeader("Calling Hedgey Batch Planner batchlockingplans");
        console.log("InvestorLockup:", hedgeyInvestorLockup);
        console.log("Batch Planner:", hedgeyBatchPlanner);
        console.log("Deployer:", deployer);
        console.log("Recipient:", recipient);
        console.log("Token:", token);
        console.log("Amount:", amount);
        console.log("Start:", start);
        console.log("Cliff:", cliff);
        console.log("Rate:", rate);
        console.log("Period:", period);
        console.log("Approve Amount:", amount);

        // Safety for mainnet
        _requireMainnetConfirmation();

        // Execute call
        vm.startBroadcast(deployerPrivateKey);

        // Ensure allowlist if caller can manage it and check paused state
        // TODO: This should ideally be run by the deployment script for the L2 contract. We'd want to allowlist the proper Hedgey contracts immediately
        {
            bytes32 ALLOWLIST_ADMIN_ROLE = keccak256("ALLOWLIST_ADMIN_ROLE");
            bool canManage = ICNSAllowlistViews(token).hasRole(ALLOWLIST_ADMIN_ROLE, deployer);
            bool isPaused = ICNSAllowlistViews(token).paused();
            bool allowlistEnabled = ICNSAllowlistViews(token).senderAllowlistEnabled();
            console.log("Token paused:", isPaused);
            console.log("Sender allowlist enabled:", allowlistEnabled);
            if (canManage && allowlistEnabled) {
                bool depAllowed = ICNSAllowlistViews(token).isSenderAllowlisted(deployer);
                bool hedgeyAllowed = ICNSAllowlistViews(token).isSenderAllowlisted(hedgeyInvestorLockup);
                bool batchPlannerAllowed = ICNSAllowlistViews(token).isSenderAllowlisted(hedgeyBatchPlanner);
                if (!depAllowed) {
                    ICNSAllowlistAdmin(token).setSenderAllowed(deployer, true);
                    console.log("Allowlisted deployer on CNS token");
                }
                if (!hedgeyAllowed) {
                    ICNSAllowlistAdmin(token).setSenderAllowed(hedgeyInvestorLockup, true);
                    console.log("Allowlisted Hedgey InvestorLockup on CNS token");
                }
                if (!batchPlannerAllowed) {
                    ICNSAllowlistAdmin(token).setSenderAllowed(hedgeyBatchPlanner, true);
                    console.log("Allowlisted Hedgey Batch Planner on CNS token");
                }
            }
        }

        // Approve token allowance to Hedgey Batch Planner if requested
        if (amount > 0) {
            bool approved = IERC20Minimal(token).approve(hedgeyBatchPlanner, amount);
            require(approved, "ERC20 approve failed");
        }
        // Prepare Plan struct for batchLockingPlans (single plan)
        Plan[] memory plans = new Plan[](1);
        plans[0] = Plan({recipient: recipient, amount: amount, start: start, cliff: cliff, rate: rate});

        // Capture detailed revert reasons from batchLockingPlans
        try IHedgeyBatchPlanner(hedgeyBatchPlanner).batchLockingPlans(
            hedgeyInvestorLockup, token, amount, plans, period, 0
        ) {
            console.log("batchLockingPlans succeeded");
        } catch Error(string memory reason) {
            console.log("batchLockingPlans Error(string):", reason);
            revert(string(abi.encodePacked("batchLockingPlans failed: ", reason)));
        } catch (bytes memory lowLevelData) {
            console.log("batchLockingPlans low-level revert data:");
            console.logBytes(lowLevelData);
            revert("batchLockingPlans failed (low-level)");
        }
        vm.stopBroadcast();

        // Summary
        console.log("\n=== Hedgey batchLockingPlans submitted ===");
        console.log("Network:", _getNetworkName(block.chainid));
        console.log("InvestorLockup:", hedgeyInvestorLockup);
        console.log("Batch Planner:", hedgeyBatchPlanner);
        console.log("Locker (InvestorLockup):", hedgeyInvestorLockup);
        console.log("Recipient:", recipient);
        console.log("Amount:", amount);

        // Post-call verification (skip plan ID verification since function doesn't return it)
        _verifyPlanCreated(recipient, token, amount, start, cliff, rate, period);
    }

    function _verifyPlanCreated(
        address recipient,
        address token,
        uint256 amount,
        uint256 start,
        uint256 cliff,
        uint256 rate,
        uint256 period
    ) internal view {
        console.log("\n=== Verifying Plan Created ===");

        uint256 count = IInvestorLockup(hedgeyInvestorLockup).balanceOf(recipient);
        require(count > 0, "No plans found for recipient");
        console.log("[OK] Recipient has", count, "plan(s)");

        // Get the most recent plan (last one created)
        uint256 latestPlanId = IInvestorLockup(hedgeyInvestorLockup).tokenOfOwnerByIndex(recipient, count - 1);
        console.log("[OK] Latest plan ID:", latestPlanId);

        (
            address plansToken,
            uint256 plansAmount,
            uint256 plansStart,
            uint256 plansCliff,
            uint256 plansRate,
            uint256 plansPeriod
        ) = IInvestorLockup(hedgeyInvestorLockup).plans(latestPlanId);

        require(plansToken == token, "plans.token mismatch");
        require(plansAmount == amount, "plans.amount mismatch");
        require(plansStart == start, "plans.start mismatch");
        require(plansCliff == cliff, "plans.cliff mismatch");
        require(plansRate == rate, "plans.rate mismatch");
        require(plansPeriod == period, "plans.period mismatch");
        console.log("[OK] Latest plan matches inputs");
    }
}
