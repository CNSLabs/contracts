// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./BaseScript.sol";
import "./ConfigLoader.sol";

/**
 * @title CreateHedgeyInvestorLockup
 * @notice Creates Hedgey vesting or locking plans using batchVestingPlans or batchLockingPlans on Linea networks.
 * @dev Uses typed interfaces and takes parameters from config files to avoid raw calldata in configuration.
 *      Defaults to vesting plans with admin controls, use locking plans only if hedgey.useInvestorLockup=true in config.
 *
 * Usage:
 *   # Default (dev) - Vesting plans
 *   forge script script/5_CreateHedgeyInvestorLockup.s.sol:CreateHedgeyInvestorLockup \
 *     --rpc-url linea-sepolia \
 *     --broadcast
 *
 *   # Explicit environment
 *   ENV=production forge script script/5_CreateHedgeyInvestorLockup.s.sol:CreateHedgeyInvestorLockup \
 *     --rpc-url linea \
 *     --broadcast
 *
 * Environment Variables:
 *   - PRIVATE_KEY: Deployer key for broadcasting
 *   - ENV: Select public config JSON (defaults to "dev")
 *
 * Configuration:
 *   All parameters are configured in config/{env}.json files under the "hedgey" section:
 *   - investorLockup: Hedgey InvestorLockup contract address
 *   - batchPlanner: Hedgey BatchPlanner contract address
 *   - tokenVestingPlans: Hedgey TokenVestingPlans contract address
 *   - period: Vesting period in seconds
 *   - useInvestorLockup: Set to 1 for locking plans, 0 for vesting plans (default)
 *   - vestingAdmin: Admin address for vesting plans (required for vesting)
 *   - adminTransferOBO: Admin transfer on behalf of flag (defaults to 0)
 *   - plans: Array of plan objects, each containing:
 *     - recipient: Plan recipient address
 *     - amount: Token amount to lock/vest
 *     - start: Vesting start timestamp
 *     - cliff: Cliff period end timestamp
 *     - rate: Tokens per second vesting rate
 *
 * Notes:
 *   - Defaults to vesting plans, set useInvestorLockup=1 in config for locking plans.
 *   - For vesting plans, vestingAdmin is required and adminTransferOBO defaults to 0.
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

interface ITokenVestingPlans {
    function createPlan(
        address recipient,
        address token,
        uint256 amount,
        uint256 start,
        uint256 cliff,
        uint256 rate,
        uint256 period,
        address vestingAdmin,
        bool adminTransferOBO
    ) external returns (uint256 newPlanId);
    function balanceOf(address owner) external view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function plans(uint256 planId)
        external
        view
        returns (
            address token,
            uint256 amount,
            uint256 start,
            uint256 cliff,
            uint256 rate,
            uint256 period,
            address vestingAdmin,
            bool adminTransferOBO
        );
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

interface IHedgeyBatchPlanner {
    function batchLockingPlans(
        address locker,
        address token,
        uint256 totalAmount,
        Plan[] calldata plans,
        uint256 period,
        uint8 mintType
    ) external;

    function batchVestingPlans(
        address locker,
        address token,
        uint256 totalAmount,
        Plan[] calldata plans,
        uint256 period,
        address vestingAdmin,
        bool adminTransferOBO,
        uint8 mintType
    ) external;
}

contract CreateHedgeyInvestorLockup is BaseScript {
    address public hedgeyInvestorLockup;
    address public hedgeyBatchPlanner;
    address public hedgeyTokenVestingPlans;


    function run() external {
        EnvConfig memory cfg = _loadEnvConfig();
        (uint256 deployerPrivateKey, address deployer) = _getDeployer();

        // Load and validate target contract addresses from config
        hedgeyInvestorLockup = cfg.hedgey.investorLockup;
        _requireNonZeroAddress(hedgeyInvestorLockup, "hedgey.investorLockup");
        _requireContract(hedgeyInvestorLockup, "hedgey.investorLockup");

        hedgeyTokenVestingPlans = cfg.hedgey.tokenVestingPlans;
        _requireNonZeroAddress(hedgeyTokenVestingPlans, "hedgey.tokenVestingPlans");
        _requireContract(hedgeyTokenVestingPlans, "hedgey.tokenVestingPlans");

        hedgeyBatchPlanner = cfg.hedgey.batchPlanner;
        _requireNonZeroAddress(hedgeyBatchPlanner, "hedgey.batchPlanner");
        _requireContract(hedgeyBatchPlanner, "hedgey.batchPlanner");

        // Load token address
        address token = cfg.l2.proxy;
        if (token == address(0)) {
            // fallback: broadcast inference used in other scripts
            token = _inferL2ProxyFromBroadcast(block.chainid);
        }
        _requireNonZeroAddress(token, "l2.proxy");

        // Load plans from config
        Plan[] memory plans = cfg.hedgey.plans;
        require(plans.length > 0, "hedgey.plans array is empty");
        
        // Validate all plans
        for (uint256 i = 0; i < plans.length; i++) {
            Plan memory plan = plans[i];
            _requireNonZeroAddress(plan.recipient, "hedgey.plans[].recipient");
            require(plan.amount > 0, "hedgey.plans[].amount must be > 0");
            require(plan.rate > 0, "hedgey.plans[].rate must be > 0");
            require(plan.start <= plan.cliff, "hedgey.plans[].start must be <= cliff");
        }

        // Calculate total amount
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < plans.length; i++) {
            totalAmount += plans[i].amount;
        }

        // Load other parameters
        uint256 period = cfg.hedgey.period;
        require(period > 0, "hedgey.period must be > 0");

        // Plan type: defaults to "vesting", use "locking" only if useInvestorLockup=true in config
        bool useInvestorLockup = cfg.hedgey.useInvestorLockup;
        string memory planType = useInvestorLockup ? "locking" : "vesting";
        address vestingAdmin = cfg.hedgey.vestingAdmin;
        bool adminTransferOBO = cfg.hedgey.adminTransferOBO;

        // Validate vesting parameters if using vesting plans (default)
        if (!useInvestorLockup) {
            _requireNonZeroAddress(vestingAdmin, "hedgey.vestingAdmin");
        }

        // Log context
        string memory header = !useInvestorLockup
            ? "Calling Hedgey Batch Planner batchVestingPlans"
            : "Calling Hedgey Batch Planner batchLockingPlans";
        _logDeploymentHeader(header);
        console.log("Plan Type:", planType);
        console.log("Use Investor Lockup:", useInvestorLockup);
        console.log("InvestorLockup:", hedgeyInvestorLockup);
        console.log("Batch Planner:", hedgeyBatchPlanner);
        console.log("Deployer:", deployer);
        console.log("Token:", token);
        console.log("Number of Plans:", plans.length);
        console.log("Total Amount:", totalAmount);
        console.log("Period:", period);
        console.log("Approve Amount:", totalAmount);
        if (!useInvestorLockup) {
            console.log("Vesting Admin:", vestingAdmin);
            console.log("Admin Transfer OBO:", adminTransferOBO);
        }
        
        // Log individual plans
        console.log("\nPlans:");
        for (uint256 i = 0; i < plans.length; i++) {
            Plan memory plan = plans[i];
            console.log("  Plan %s:", i + 1);
            console.log("    Recipient: %s", plan.recipient);
            console.log("    Amount: %s", plan.amount);
            console.log("    Start: %s", plan.start);
            console.log("    Cliff: %s", plan.cliff);
            console.log("    Rate: %s", plan.rate);
        }

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
        if (totalAmount > 0) {
            bool approved = IERC20Minimal(token).approve(hedgeyBatchPlanner, totalAmount);
            require(approved, "ERC20 approve failed");
        }

        // Execute the appropriate batch function based on plan type
        if (!useInvestorLockup) {
            // Capture detailed revert reasons from batchVestingPlans
            try IHedgeyBatchPlanner(hedgeyBatchPlanner)
                .batchVestingPlans(
                    hedgeyTokenVestingPlans, token, totalAmount, plans, period, vestingAdmin, adminTransferOBO, 0
                ) {
                console.log("batchVestingPlans succeeded");
            } catch Error(string memory reason) {
                console.log("batchVestingPlans Error(string):", reason);
                revert(string(abi.encodePacked("batchVestingPlans failed: ", reason)));
            } catch (bytes memory lowLevelData) {
                console.log("batchVestingPlans low-level revert data:");
                console.logBytes(lowLevelData);
                revert("batchVestingPlans failed (low-level)");
            }
        } else {
            // Capture detailed revert reasons from batchLockingPlans
            try IHedgeyBatchPlanner(hedgeyBatchPlanner)
                .batchLockingPlans(hedgeyInvestorLockup, token, totalAmount, plans, period, 0) {
                console.log("batchLockingPlans succeeded");
            } catch Error(string memory reason) {
                console.log("batchLockingPlans Error(string):", reason);
                revert(string(abi.encodePacked("batchLockingPlans failed: ", reason)));
            } catch (bytes memory lowLevelData) {
                console.log("batchLockingPlans low-level revert data:");
                console.logBytes(lowLevelData);
                revert("batchLockingPlans failed (low-level)");
            }
        }
        vm.stopBroadcast();

        // Summary
        string memory summaryHeader = !useInvestorLockup
            ? "=== Hedgey batchVestingPlans submitted ==="
            : "=== Hedgey batchLockingPlans submitted ===";
        console.log(summaryHeader);
        console.log("Network:", _getNetworkName(block.chainid));
        console.log("Plan Type:", planType);
        console.log("Use Investor Lockup:", useInvestorLockup);
        console.log("InvestorLockup:", hedgeyInvestorLockup);
        console.log("Batch Planner:", hedgeyBatchPlanner);
        console.log("Number of Plans:", plans.length);
        console.log("Total Amount:", totalAmount);
        if (!useInvestorLockup) {
            console.log("Vesting Admin:", vestingAdmin);
            console.log("Admin Transfer OBO:", adminTransferOBO);
        }

        // Post-call verification (works for both locking and vesting plans)
        _verifyPlansCreated(plans, token, period, useInvestorLockup, vestingAdmin, adminTransferOBO);
    }

    function _verifyPlansCreated(
        Plan[] memory plans,
        address token,
        uint256 period,
        bool useInvestorLockup,
        address vestingAdmin,
        bool adminTransferOBO
    ) internal view {
        console.log("\n=== Verifying Plans Created ===");

        // Use the correct contract based on plan type
        address targetContract = useInvestorLockup ? hedgeyInvestorLockup : hedgeyTokenVestingPlans;
        string memory planType = useInvestorLockup ? "locking" : "vesting";
        console.log("Verifying", planType, "plans in contract:", targetContract);

        // Verify each plan
        for (uint256 i = 0; i < plans.length; i++) {
            Plan memory plan = plans[i];
            console.log("Verifying plan %s for recipient: %s", i + 1, plan.recipient);

            uint256 count = IInvestorLockup(targetContract).balanceOf(plan.recipient);
            require(count > 0, "No plans found for recipient");
            console.log("[OK] Recipient has %s %s plan(s)", count, planType);

            // Get the most recent plan (last one created)
            uint256 latestPlanId = IInvestorLockup(targetContract).tokenOfOwnerByIndex(plan.recipient, count - 1);
            console.log("[OK] Latest plan ID: %s", latestPlanId);

            if (useInvestorLockup) {
                // For locking plans, use the simpler interface
                (
                    address plansToken,
                    uint256 plansAmount,
                    uint256 plansStart,
                    uint256 plansCliff,
                    uint256 plansRate,
                    uint256 plansPeriod
                ) = IInvestorLockup(targetContract).plans(latestPlanId);

                require(plansToken == token, "plans.token mismatch");
                require(plansAmount == plan.amount, "plans.amount mismatch");
                require(plansStart == plan.start, "plans.start mismatch");
                require(plansCliff == plan.cliff, "plans.cliff mismatch");
                require(plansRate == plan.rate, "plans.rate mismatch");
                require(plansPeriod == period, "plans.period mismatch");
            } else {
                // For vesting plans, use the extended interface
                (
                    address plansToken,
                    uint256 plansAmount,
                    uint256 plansStart,
                    uint256 plansCliff,
                    uint256 plansRate,
                    uint256 plansPeriod,
                    address plansVestingAdmin,
                    bool plansAdminTransferOBO
                ) = ITokenVestingPlans(targetContract).plans(latestPlanId);

                require(plansToken == token, "plans.token mismatch");
                require(plansAmount == plan.amount, "plans.amount mismatch");
                require(plansStart == plan.start, "plans.start mismatch");
                require(plansCliff == plan.cliff, "plans.cliff mismatch");
                require(plansRate == plan.rate, "plans.rate mismatch");
                require(plansPeriod == period, "plans.period mismatch");
                require(plansVestingAdmin == vestingAdmin, "plans.vestingAdmin mismatch");
                require(plansAdminTransferOBO == adminTransferOBO, "plans.adminTransferOBO mismatch");
            }
            console.log("[OK] Plan %s matches inputs", i + 1);
        }
        console.log("[OK] All %s %s plans verified successfully", plans.length, planType);
    }
}
