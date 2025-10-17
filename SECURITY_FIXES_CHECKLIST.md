# Security Fixes Checklist

Based on the CNSTokenL2 Security Audit Report (October 15, 2025)

---

## 🔴 Priority 0: CRITICAL - Must Fix Before Deployment

### 1. Initialization Frontrunning Protection
- [ ] Update deployment script to use atomic initialization
- [ ] Implement initialization in proxy constructor with `abi.encodeWithSelector`
- [ ] Add test case: `testCannotFrontrunInitialization()`
- [ ] Verify proxy is initialized immediately after deployment
- [ ] Document atomic initialization pattern in deployment docs

**Code Change Required:**
```solidity
// In deployment script
bytes memory initData = abi.encodeWithSelector(
    CNSTokenL2.initialize.selector,
    admin, bridge, l1Token, name, symbol, decimals
);
ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
```

**Test Script:** `script/2_DeployCNSTokenL2.s.sol`  
**Severity:** HIGH  
**Estimated Time:** 1 day

---

## 🟠 Priority 1: HIGH - Should Fix Before Deployment

### 2. Bridge Address Validation
- [ ] Add contract validation check in `initialize()`
- [ ] Require `bridge_.code.length > 0`
- [ ] Add event emission: `BridgeSet(bridge_)`
- [ ] Add test case: `testInitializeRevertsIfBridgeIsEOA()`
- [ ] Update initialization validation error handling

**Code Change Required:**
```solidity
// In CNSTokenL2.sol initialize()
require(bridge_.code.length > 0, "bridge must be contract");
bridge = bridge_;
emit BridgeSet(bridge_);
```

**File:** `src/CNSTokenL2.sol` (line ~53)  
**Severity:** HIGH  
**Estimated Time:** 1 day

---

### 3. Role Separation and Multisig Setup
- [ ] Deploy Gnosis Safe multisig (3-of-5 or 4-of-7 recommended)
- [ ] Update `initialize()` to accept separate role addresses
- [ ] Create initialization parameters:
  - `multisig_` for DEFAULT_ADMIN_ROLE and UPGRADER_ROLE
  - `emergencyPauser_` for PAUSER_ROLE
  - `allowlistAdmin_` for ALLOWLIST_ADMIN_ROLE
- [ ] Update deployment script with new parameters
- [ ] Add tests for role separation
- [ ] Document role holder responsibilities
- [ ] Establish key rotation procedures

**Code Change Required:**
```solidity
function initialize(
    address multisig_,
    address emergencyPauser_,
    address allowlistAdmin_,
    address bridge_,
    address l1Token_,
    string memory name_,
    string memory symbol_,
    uint8 decimals_
) external initializer {
    // ... validation ...
    _grantRole(DEFAULT_ADMIN_ROLE, multisig_);
    _grantRole(UPGRADER_ROLE, multisig_);
    _grantRole(PAUSER_ROLE, emergencyPauser_);
    _grantRole(PAUSER_ROLE, multisig_);  // Backup
    _grantRole(ALLOWLIST_ADMIN_ROLE, allowlistAdmin_);
    _grantRole(ALLOWLIST_ADMIN_ROLE, multisig_);  // Backup
}
```

**File:** `src/CNSTokenL2.sol` (line 35-67)  
**Severity:** MEDIUM-HIGH  
**Estimated Time:** 2-3 days

---

### 4. Allowlist UX Improvement

**Choose One Approach:**

#### Option A: Auto-Allowlist Bridge Recipients (RECOMMENDED)
- [ ] Modify `mint()` function to auto-allowlist recipients
- [ ] Add automatic allowlist logic when minting
- [ ] Update tests for auto-allowlist behavior
- [ ] Document auto-allowlist behavior in NatSpec

**Code Change:**
```solidity
function mint(address _recipient, uint256 _amount) external onlyBridge {
    if (_senderAllowlistEnabled && !_senderAllowlisted[_recipient]) {
        _setSenderAllowlist(_recipient, true);
    }
    _mint(_recipient, _amount);
}
```

#### Option B: Improved Documentation + Batch Function
- [ ] Add comprehensive NatSpec documentation
- [ ] Improve batch function with better error handling
- [ ] Document user flow: bridge → allowlist → transfer
- [ ] Create user guide for allowlist process

**File:** `src/CNSTokenL2.sol` (lines 103-104 and mint function)  
**Severity:** MEDIUM-HIGH (UX)  
**Estimated Time:** 1-2 days

---

## 🟡 Priority 2: MEDIUM - Recommended Fixes

### 5. Event Emissions for Critical State Changes
- [ ] Define new events:
  - `Initialized(address indexed admin, address indexed bridge, address indexed l1Token, ...)`
  - `BridgeSet(address indexed bridge)`
  - `L1TokenSet(address indexed l1Token)`
- [ ] Emit events in `initialize()` function
- [ ] Update tests to check event emissions
- [ ] Verify events in deployment script

**Code Change:**
```solidity
event Initialized(address indexed admin, address indexed bridge, address indexed l1Token, string name, string symbol, uint8 decimals);
event BridgeSet(address indexed bridge);
event L1TokenSet(address indexed l1Token);

function initialize(...) external initializer {
    // ... initialization logic ...
    emit BridgeSet(bridge_);
    emit L1TokenSet(l1Token_);
    emit Initialized(admin_, bridge_, l1Token_, name_, symbol_, decimals_);
}
```

**File:** `src/CNSTokenL2.sol` (lines 53, 56)  
**Severity:** MEDIUM  
**Estimated Time:** 1 day

---

### 6. Batch Operation Gas Limits
- [ ] Add `MAX_BATCH_SIZE` constant (value: 200)
- [ ] Add validation in `setSenderAllowedBatch()`
- [ ] Require batch length > 0 and <= MAX_BATCH_SIZE
- [ ] Add test: `testBatchAllowlistRevertsIfTooLarge()`
- [ ] Add test: `testBatchAllowlistSucceedsWithinLimit()`
- [ ] Document batch size limits in NatSpec

**Code Change:**
```solidity
uint256 public constant MAX_BATCH_SIZE = 200;

function setSenderAllowedBatch(address[] calldata accounts, bool allowed) 
    external onlyRole(ALLOWLIST_ADMIN_ROLE) {
    require(accounts.length > 0, "empty batch");
    require(accounts.length <= MAX_BATCH_SIZE, "batch too large");
    // ... rest of function
}
```

**File:** `src/CNSTokenL2.sol` (line 89-94)  
**Severity:** MEDIUM  
**Estimated Time:** 1 day

---

### 7. Upgrade Timelock Implementation

**Choose One Approach:**

#### Option A: OpenZeppelin TimelockController (RECOMMENDED)
- [ ] Import TimelockController from OpenZeppelin
- [ ] Deploy TimelockController with 48-72 hour delay
- [ ] Configure proposers (multisig)
- [ ] Configure executors (anyone after delay)
- [ ] Grant UPGRADER_ROLE to timelock contract
- [ ] Optionally revoke UPGRADER_ROLE from multisig
- [ ] Document timelock upgrade process
- [ ] Add tests for timelock upgrade flow

**Deployment Change:**
```solidity
import "@openzeppelin/contracts/governance/TimelockController.sol";

TimelockController timelock = new TimelockController(
    48 hours,
    proposers,
    executors,
    admin
);
token.grantRole(token.UPGRADER_ROLE(), address(timelock));
```

#### Option B: Custom Upgrade Delay
- [ ] Add `PendingUpgrade` struct
- [ ] Add `UPGRADE_DELAY` constant (48 hours)
- [ ] Implement `proposeUpgrade()` function
- [ ] Implement `executeUpgrade()` function
- [ ] Implement `cancelUpgrade()` function
- [ ] Implement `emergencyUpgrade()` function (requires pause)
- [ ] Add events for upgrade lifecycle
- [ ] Add comprehensive upgrade tests

**File:** New upgrade management code in `src/CNSTokenL2.sol` or separate contract  
**Severity:** MEDIUM  
**Estimated Time:** 3-5 days

---

### 8. Zero Address Validation in Setters
- [ ] Define `ZeroAddress` custom error
- [ ] Add validation in `setSenderAllowed()`
- [ ] Add validation in `setSenderAllowedBatch()`
- [ ] Add test: `testCannotAllowlistZeroAddress()`
- [ ] Add test: `testBatchCannotIncludeZeroAddress()`

**Code Change:**
```solidity
error ZeroAddress();

function setSenderAllowed(address account, bool allowed) 
    external onlyRole(ALLOWLIST_ADMIN_ROLE) {
    if (account == address(0)) revert ZeroAddress();
    _setSenderAllowlist(account, allowed);
}

function setSenderAllowedBatch(address[] calldata accounts, bool allowed) 
    external onlyRole(ALLOWLIST_ADMIN_ROLE) {
    require(accounts.length > 0, "empty batch");
    require(accounts.length <= MAX_BATCH_SIZE, "batch too large");
    for (uint256 i; i < accounts.length; ++i) {
        if (accounts[i] == address(0)) revert ZeroAddress();
        _setSenderAllowlist(accounts[i], allowed);
    }
    emit SenderAllowlistBatchUpdated(accounts, allowed);
}
```

**File:** `src/CNSTokenL2.sol` (line 85)  
**Severity:** MEDIUM  
**Estimated Time:** 1 day

---

## 🟢 Priority 3: LOW - Optional Improvements

### 9. Custom Errors for Gas Optimization
- [ ] Define custom errors:
  - `InvalidAdmin()`
  - `InvalidBridge()`
  - `InvalidL1Token()`
  - `SenderNotAllowlisted()`
  - `BatchTooLarge()`
  - `EmptyBatch()`
  - `ZeroAddress()`
- [ ] Replace all `require()` statements with custom errors
- [ ] Replace string `revert()` with custom errors
- [ ] Update tests to check for custom errors
- [ ] Document gas savings in comments

**Code Change:**
```solidity
error InvalidAdmin();
error InvalidBridge();
error InvalidL1Token();
error SenderNotAllowlisted();
error BatchTooLarge();
error EmptyBatch();
error ZeroAddress();

// Usage:
if (admin_ == address(0)) revert InvalidAdmin();
if (!_senderAllowlisted[from]) revert SenderNotAllowlisted();
```

**File:** `src/CNSTokenL2.sol` (lines 43-45, 104)  
**Severity:** LOW (Gas Optimization)  
**Estimated Time:** 2 days

---

### 10. Lock Pragma Version
- [ ] Change pragma from `^0.8.25` to `0.8.25` in production deployment
- [ ] Keep caret version for development/testing
- [ ] Document compiler version in deployment docs
- [ ] Verify bytecode consistency

**Code Change:**
```solidity
// Change from:
pragma solidity ^0.8.25;

// To (for production):
pragma solidity 0.8.25;
```

**File:** `src/CNSTokenL2.sol` (line 2)  
**Severity:** INFORMATIONAL  
**Estimated Time:** 5 minutes

---

## 🧪 Testing Enhancements

### Missing Critical Tests

#### Test File: `test/CNSTokenL2.security.t.sol`
- [ ] Create new security test file
- [ ] Test: `testInitializationIsAtomicInDeployment()`
- [ ] Test: `testBridgeMustBeContract()`
- [ ] Test: `testCannotAllowlistZeroAddress()`
- [ ] Test: `testBatchSizeLimit()`
- [ ] Test: `testRoleManagement()`
  - Grant roles
  - Revoke roles
  - Non-admin cannot grant roles
  - Revoked role cannot perform actions

**Estimated Time:** 2 days

---

#### Additional Test Coverage
- [ ] Test: `testTransferFromRespectsAllowlist()`
- [ ] Test: `testPermitWithAllowlistEnabled()`
- [ ] Test: `testSelfTransferWithAllowlist()`
- [ ] Test: `testAdminCanGrantRoles()`
- [ ] Test: `testNonAdminCannotGrantRoles()`
- [ ] Test: `testAdminCanRevokeRoles()`
- [ ] Test: `testRevokedRoleCannotPerformActions()`

**Estimated Time:** 2 days

---

#### Fuzz Testing: `test/CNSTokenL2.fuzz.t.sol`
- [ ] Create fuzz test file
- [ ] Test: `testFuzzAllowlistManagement(address account, bool allowed)`
- [ ] Test: `testFuzzTransferWithAllowlist(address from, address to, uint256 amount)`
- [ ] Test: `testFuzzBatchOperations(address[] accounts, bool allowed)`

**Estimated Time:** 2 days

---

#### Invariant Testing: `test/CNSTokenL2.invariant.t.sol`
- [ ] Create invariant test file
- [ ] Create token handler contract for invariant testing
- [ ] Invariant: Total supply only increases via mints or decreases via burns
- [ ] Invariant: Paused state blocks all transfers
- [ ] Invariant: Sum of balances equals total supply
- [ ] Invariant: Only bridge can mint

**Estimated Time:** 3 days

---

## 📋 Deployment Checklist

### Pre-Deployment
- [ ] All P0 (critical) issues resolved
- [ ] Atomic initialization implemented in deployment script
- [ ] Bridge contract address verified (is a contract, not EOA)
- [ ] L1 token address verified
- [ ] All tests passing (22+ tests including new security tests)
- [ ] Code frozen for review period (7-14 days)
- [ ] External audit completed (recommended for production)
- [ ] Multisig deployed and tested
- [ ] All role holders identified and documented
- [ ] Timelock deployed (if using separate timelock)

### Deployment
- [ ] Deploy implementation contract
- [ ] Verify implementation contract on block explorer
- [ ] Deploy proxy with atomic initialization
- [ ] Verify proxy contract on block explorer
- [ ] Verify all initialization parameters correct
- [ ] Grant roles to appropriate addresses
- [ ] Verify role assignments
- [ ] Test basic functionality (mint, transfer with allowlist, pause)

### Post-Deployment
- [ ] Configure monitoring and alerting:
  - Large transfers
  - Role changes
  - Upgrade attempts
  - Pause/unpause events
- [ ] Incident response plan prepared
- [ ] User documentation published
- [ ] API documentation for allowlist management
- [ ] Bug bounty program launched (recommended)
- [ ] Testnet deployment completed and tested
- [ ] Community announcement and transparency report

---

## 📊 Progress Tracking

### Summary by Priority

| Priority | Total Items | Completed | In Progress | Not Started |
|----------|-------------|-----------|-------------|-------------|
| P0 (Critical) | 1 | 0 | 0 | 1 |
| P1 (High) | 4 | 0 | 0 | 4 |
| P2 (Medium) | 4 | 0 | 0 | 4 |
| P3 (Low) | 2 | 0 | 0 | 2 |
| Testing | 4 files | 0 | 0 | 4 |
| **TOTAL** | **15** | **0** | **0** | **15** |

---

## ⏱️ Estimated Timeline

### Quick Fixes (P0 + P1 Essential)
- Priority 0: 1 day
- Priority 1 (items 2-3): 3-4 days
- **Total for minimal deployment readiness**: 4-5 days

### Recommended Fixes (P0 + P1 + P2)
- Priority 0: 1 day
- Priority 1: 4-6 days
- Priority 2: 6-8 days
- **Total for production readiness**: 11-15 days (2-3 weeks)

### Complete Implementation (All Priorities)
- Priority 0: 1 day
- Priority 1: 4-6 days
- Priority 2: 6-8 days
- Priority 3: 2-3 days
- Testing: 7-9 days
- **Total**: 20-27 days (3-4 weeks)

### With External Audit
- Internal fixes: 2-3 weeks
- External audit: 2-4 weeks
- Audit response: 1 week
- **Total**: 5-8 weeks

---

## 📝 Notes

### Dependencies Between Tasks
- Item 1 (atomic initialization) should be completed first
- Item 3 (role separation) affects deployment process
- Item 4 (allowlist UX) decision affects testing strategy
- Item 7 (timelock) affects role configuration

### Breaking Changes
Items that require contract redeployment:
- ✅ Item 2 (bridge validation) - changes `initialize()`
- ✅ Item 3 (role separation) - changes `initialize()` signature
- ✅ Item 4 Option A (auto-allowlist) - changes `mint()` behavior
- ✅ Item 5 (events) - changes `initialize()`
- ✅ Item 6 (batch limits) - changes `setSenderAllowedBatch()`
- ✅ Item 7 Option B (custom timelock) - adds new functions
- ✅ Item 9 (custom errors) - changes all error handling

### Non-Breaking Changes
Items that only affect deployment/testing:
- ✅ Item 1 (deployment script)
- ✅ Item 10 (pragma)
- ✅ All testing enhancements

---

## 🎯 Minimum Viable Deployment

For fastest path to production (not recommended for mainnet):
1. ✅ Item 1: Atomic initialization (MUST FIX)
2. ✅ Item 2: Bridge validation (SHOULD FIX)
3. ✅ Item 3: Use multisig for admin (SHOULD FIX)
4. ✅ Item 4: Document allowlist UX (SHOULD ADDRESS)

**Estimated time: 5-7 days**

---

## 🏆 Recommended Production Deployment

For secure mainnet deployment:
1. ✅ All P0 items
2. ✅ All P1 items
3. ✅ All P2 items
4. ✅ Security tests (at minimum)
5. ✅ External audit (if TVL > $1M)

**Estimated time: 3-8 weeks (depending on audit)**

---

## 📞 Questions or Issues?

For clarification on any checklist item:
1. Reference the Security Audit Report section number
2. Check the code location (file and line numbers provided)
3. Review the example code changes
4. Consult with security team or auditor

---

**Last Updated:** October 17, 2025  
**Based On:** CNSTokenL2_Security_Audit_Report.md  
**Contract Version:** v1.0  
**Status:** Not Started

