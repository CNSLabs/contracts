// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./BaseScript.sol";

/**
 * @title CreateHedgeyInvestorLockup
 * @notice Calls Hedgey's InvestorLockup contract `createPlan` on Linea networks.
 * @dev Uses a typed interface for `createPlan` and takes parameters from env
 *      variables to avoid raw calldata in configuration.
 *
 * Usage (Linea Sepolia example):
 *   forge script script/4_CreateHedgeyInvestorLockup.s.sol:CreateHedgeyInvestorLockup \
 *     --rpc-url linea_sepolia \
 *     --broadcast
 *
 * Required env vars:
 *   - PRIVATE_KEY            : Deployer key for broadcasting
 *   - HEDGEY_INVESTOR_LOCKUP : Hedgey InvestorLockup contract address on target chain
 *   - HEDGEY_RECIPIENT       : Recipient address for the vesting plan
 *   - HEDGEY_AMOUNT          : Total amount (uint256, base units)
 *   - HEDGEY_START           : Start timestamp (uint256)
 *   - HEDGEY_CLIFF           : Cliff timestamp (uint256)
 *   - HEDGEY_RATE            : Release rate per period (uint256)
 *   - HEDGEY_PERIOD          : Period length in seconds (uint256)
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
    function isAllowlisted(address account) external view returns (bool);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function paused() external view returns (bool);
}

interface ICNSAllowlistAdmin {
    function setAllowlist(address account, bool allowed) external;
}

contract CreateHedgeyInvestorLockup is BaseScript {
    address public hedgeyInvestorLockup;

    function run() external {
        (uint256 deployerPrivateKey, address deployer) = _getDeployer();

        // Load and validate target contract address
        hedgeyInvestorLockup = vm.envAddress("HEDGEY_INVESTOR_LOCKUP");
        _requireNonZeroAddress(hedgeyInvestorLockup, "HEDGEY_INVESTOR_LOCKUP");
        _requireContract(hedgeyInvestorLockup, "HEDGEY_INVESTOR_LOCKUP");

        // Load parameters
        address recipient = vm.envAddress("HEDGEY_RECIPIENT");
        address token = vm.envAddress("CNS_TOKEN_L2_PROXY");
        uint256 amount = vm.envUint("HEDGEY_AMOUNT");
        uint256 start = vm.envUint("HEDGEY_START");
        uint256 cliff = vm.envUint("HEDGEY_CLIFF");
        uint256 rate = vm.envUint("HEDGEY_RATE");
        uint256 period = vm.envUint("HEDGEY_PERIOD");

        _requireNonZeroAddress(recipient, "HEDGEY_RECIPIENT");
        _requireNonZeroAddress(token, "CNS_TOKEN_L2_PROXY");
        require(amount > 0, "HEDGEY_AMOUNT must be > 0");
        require(period > 0, "HEDGEY_PERIOD must be > 0");
        require(rate > 0, "HEDGEY_RATE must be > 0");
        require(start <= cliff, "start must be <= cliff");

        // Log context
        _logDeploymentHeader("Calling Hedgey InvestorLockup createPlan");
        console.log("InvestorLockup:", hedgeyInvestorLockup);
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

        // Check current token balance of deployer before approve/createPlan
        // uint256 preBalance = IERC20Minimal(token).balanceOf(deployer);
        // uint8 tokenDecimals = IERC20Minimal(token).decimals();
        // console.log("Pre-balance (raw):", preBalance);
        // console.log("Token decimals:", tokenDecimals);
        // console.log(deployer, hedgeyInvestorLockup);
        // uint256 preAllowance = IERC20Minimal(token).allowance(deployer, hedgeyInvestorLockup);
        // console.log("Current allowance (owner=deployer -> spender=InvestorLockup):", preAllowance);

        // Ensure allowlist if caller can manage it and check paused state
        {
            bytes32 ALLOWLIST_ADMIN_ROLE = keccak256("ALLOWLIST_ADMIN_ROLE");
            bool canManage = ICNSAllowlistViews(token).hasRole(ALLOWLIST_ADMIN_ROLE, deployer);
            bool isPaused = ICNSAllowlistViews(token).paused();
            console.log("Token paused:", isPaused);
            if (canManage) {
                bool depAllowed = ICNSAllowlistViews(token).isAllowlisted(deployer);
                bool hedgeyAllowed = ICNSAllowlistViews(token).isAllowlisted(hedgeyInvestorLockup);
                if (!depAllowed) {
                    ICNSAllowlistAdmin(token).setAllowlist(deployer, true);
                    console.log("Allowlisted deployer on CNS token");
                }
                if (!hedgeyAllowed) {
                    ICNSAllowlistAdmin(token).setAllowlist(hedgeyInvestorLockup, true);
                    console.log("Allowlisted Hedgey InvestorLockup on CNS token");
                }
            }
        }

        // Approve token allowance to Hedgey if requested
        if (amount > 0) {
            bool approved = IERC20Minimal(token).approve(hedgeyInvestorLockup, amount);
            require(approved, "ERC20 approve failed");
        }
        uint256 newPlanId;
        // Capture detailed revert reasons from createPlan
        try IInvestorLockup(hedgeyInvestorLockup).createPlan(recipient, token, amount, start, cliff, rate, period)
        returns (uint256 planId_) {
            newPlanId = planId_;
        } catch Error(string memory reason) {
            console.log("createPlan Error(string):", reason);
            revert(string(abi.encodePacked("createPlan failed: ", reason)));
        } catch (bytes memory lowLevelData) {
            console.log("createPlan low-level revert data:");
            console.logBytes(lowLevelData);
            revert("createPlan failed (low-level)");
        }
        vm.stopBroadcast();

        // Summary
        console.log("\n=== Hedgey createPlan submitted ===");
        console.log("Network:", _getNetworkName(block.chainid));
        console.log("InvestorLockup:", hedgeyInvestorLockup);
        // console.log("New Plan ID:", newPlanId);

        // Post-call verification
        _verifyPlan(recipient, token, amount, start, cliff, rate, period, newPlanId);
    }

    function _verifyPlan(
        address recipient,
        address token,
        uint256 amount,
        uint256 start,
        uint256 cliff,
        uint256 rate,
        uint256 period,
        uint256 planId
    ) internal view {
        console.log("\n=== Verifying Plan State ===");

        uint256 count = IInvestorLockup(hedgeyInvestorLockup).balanceOf(recipient);

        uint256 indexedPlanId = IInvestorLockup(hedgeyInvestorLockup).tokenOfOwnerByIndex(recipient, count - 1);
        require(indexedPlanId == planId, "tokenOfOwnerByIndex mismatch");
        console.log("[OK] tokenOfOwnerByIndex(recipient,0) matches planId");

        (
            address plansToken,
            uint256 plansAmount,
            uint256 plansStart,
            uint256 plansCliff,
            uint256 plansRate,
            uint256 plansPeriod
        ) = IInvestorLockup(hedgeyInvestorLockup).plans(planId);

        require(plansToken == token, "plans.token mismatch");
        require(plansAmount == amount, "plans.amount mismatch");
        require(plansStart == start, "plans.start mismatch");
        require(plansCliff == cliff, "plans.cliff mismatch");
        require(plansRate == rate, "plans.rate mismatch");
        require(plansPeriod == period, "plans.period mismatch");
        console.log("[OK] plans(planId) matches inputs");
    }
}
