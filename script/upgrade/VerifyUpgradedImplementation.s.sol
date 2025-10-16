// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../BaseScript.sol";

/**
 * @title VerifyUpgradedImplementation
 * @notice Verifies the current implementation behind a UUPS proxy after a Safe-executed upgrade
 * @dev Uses Foundry FFI to call `forge verify-contract`. Requires FOUNDRY_FFI=1.
 *
 * Env vars:
 * - TARGET_CONTRACT: proxy address just upgraded
 * - RPC_URL: rpc to read storage if needed by tools (optional for verify)
 * - ETHERSCAN_API_KEY / LINEA_ETHERSCAN_API_KEY: per-chain explorer API keys
 * - CONTRACT_PATH: optional override for contract path (default: src/CNSTokenL2.sol:CNSTokenL2)
 * - ALSO_MARK_PROXY=1: if set on Linea networks, call explorer to mark proxy verified
 *
 * Usage:
 *   source script/upgrade/input_params.env
 *   forge script script/upgrade/VerifyUpgradedImplementation.s.sol:VerifyUpgradedImplementation \
 *     --rpc-url $RPC_URL --broadcast
 */
contract VerifyUpgradedImplementation is BaseScript {
    bytes32 constant EIP1967_IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address public proxyAddress;
    address public implementationAddress;
    string public contractPath;

    function run() external {
        _logDeploymentHeader("Post-Upgrade Implementation Verification");

        proxyAddress = _readProxyFromEnv();
        _requireNonZeroAddress(proxyAddress, "TARGET_CONTRACT");
        _requireContract(proxyAddress, "TARGET_CONTRACT (proxy)");

        implementationAddress = _loadImplementation(proxyAddress);

        console.log("Proxy:", proxyAddress);
        console.log("Implementation:", implementationAddress);

        contractPath = _resolveContractPath();
        _verifyImplementation(implementationAddress, contractPath);

        if (_shouldMarkProxy()) {
            _markProxyOnLinea(proxyAddress, implementationAddress);
        }

        console.log("\nDone.");
    }

    function _readProxyFromEnv() internal view returns (address) {
        address a = vm.envOr("TARGET_CONTRACT", address(0));
        return a;
    }

    function _loadImplementation(address proxyAddr) internal view returns (address) {
        bytes32 raw = vm.load(proxyAddr, EIP1967_IMPL_SLOT);
        return address(uint160(uint256(raw)));
    }

    function _resolveContractPath() internal view returns (string memory) {
        // Allow override; default to CNSTokenL2
        try vm.envString("CONTRACT_PATH") returns (string memory overridePath) {
            if (bytes(overridePath).length > 0) return overridePath;
        } catch {}
        return "src/CNSTokenL2.sol:CNSTokenL2";
    }

    function _verifyImplementation(address impl, string memory path) internal {
        // Pick API key variable name based on network; Foundry handles --chain routing.
        string memory chainParam = _getChainParam(block.chainid);
        if (bytes(chainParam).length == 0) {
            console.log("[INFO] No built-in chain param; print manual command");
            _logVerificationCommand(impl, path);
            return;
        }

        string memory apiKeyVar = _apiKeyEnvForChain();
        string memory apiKey = vm.envOr(apiKeyVar, string(""));
        if (bytes(apiKey).length == 0) {
            console.log("[WARN] %s not set; printing manual command", apiKeyVar);
            _logVerificationCommand(impl, path);
            return;
        }

        // Build: forge verify-contract <impl> <path> <chainParam> --etherscan-api-key <key> --watch
        string[] memory cmd = new string[](9);
        cmd[0] = "forge";
        cmd[1] = "verify-contract";
        cmd[2] = vm.toString(impl);
        cmd[3] = path;
        // Split chainParam into two tokens if present ("--chain X")
        // For simplicity use a shell wrapper via bash -lc to include full command reliably.
        string memory full = string.concat(
            "forge verify-contract ",
            vm.toString(impl),
            " ",
            path,
            " ",
            chainParam,
            " --etherscan-api-key ",
            apiKey,
            " --watch"
        );

        _bash(full);
        console.log("Submitted verification to explorer (watching)");
    }

    function _apiKeyEnvForChain() internal view returns (string memory) {
        if (block.chainid == ETHEREUM_MAINNET || block.chainid == ETHEREUM_SEPOLIA) {
            return "ETHERSCAN_API_KEY";
        }
        if (block.chainid == LINEA_MAINNET || block.chainid == LINEA_SEPOLIA) {
            return "LINEA_ETHERSCAN_API_KEY";
        }
        return "ETHERSCAN_API_KEY"; // default
    }

    function _shouldMarkProxy() internal view returns (bool) {
        bool mark = vm.envOr("ALSO_MARK_PROXY", false);
        return mark && (block.chainid == LINEA_MAINNET || block.chainid == LINEA_SEPOLIA);
    }

    function _markProxyOnLinea(address proxyAddr, address implAddr) internal {
        console.log("\n[INFO] Marking proxy as verified on Linea explorer...");
        string memory apiKey = vm.envOr("LINEA_ETHERSCAN_API_KEY", string(""));
        if (bytes(apiKey).length == 0) {
            console.log("[WARN] LINEA_ETHERSCAN_API_KEY not set; skipping proxy mark");
            return;
        }

        // Reuse the existing VerifyProxyOnExplorer flow through curl. Prefer v2, fallback to v1.
        string memory defaultUrlV2 = block.chainid == LINEA_MAINNET
            ? "https://api.lineascan.build/v2/api"
            : "https://api-sepolia.lineascan.build/v2/api";
        string memory defaultUrlV1 = block.chainid == LINEA_MAINNET
            ? "https://api.lineascan.build/api"
            : "https://api-sepolia.lineascan.build/api";
        string memory urlV2 = vm.envOr("LINEA_VERIFIER_URL", defaultUrlV2);
        string memory urlV1 = vm.envOr("LINEA_VERIFIER_URL_V1", defaultUrlV1);

        string memory submitCmd = string.concat(
            // v2 attempt
            "BODY_V2=$(curl -s -X POST ",
            urlV2,
            " -H 'User-Agent: foundry-ffi/1.0' -H 'Accept: application/json' -H 'Content-Type: application/x-www-form-urlencoded' -H 'X-Api-Key: ",
            apiKey,
            "'",
            " -d chainid=",
            vm.toString(block.chainid),
            " -d module=contract -d action=verifyproxycontract",
            " -d address=",
            vm.toString(proxyAddr),
            " -d expectedimplementation=",
            vm.toString(implAddr),
            "); CODE_V2=$(echo \"$BODY_V2\" | jq -r '.status // .code // empty' 2>/dev/null); ",
            "GUID_V2=$(echo \"$BODY_V2\" | jq -r '.result // .data // .guid // empty' 2>/dev/null); ",
            "if echo \"$BODY_V2\" | grep -qi 'already verified'; then echo 'Already Verified'; ",
            "elif [[ -n \"$GUID_V2\" ]]; then echo \"v2|$GUID_V2\"; ",
            "else ",
            // v1 fallback
            "BODY_V1=$(curl -s -X POST ",
            urlV1,
            " -H 'User-Agent: foundry-ffi/1.0' -H 'Accept: application/json' -H 'Content-Type: application/x-www-form-urlencoded'",
            " -d module=contract -d action=verifyproxycontract",
            " -d address=",
            vm.toString(proxyAddr),
            " -d expectedimplementation=",
            vm.toString(implAddr),
            " -d apikey=",
            apiKey,
            "); GUID_V1=$(echo \"$BODY_V1\" | jq -r '.result // .data // .guid // empty' 2>/dev/null); ",
            "if echo \"$BODY_V1\" | grep -qi 'already verified'; then echo 'Already Verified'; ",
            "elif [[ -n \"$GUID_V1\" ]]; then echo \"v1|$GUID_V1\"; ",
            "else echo \"ERR|$BODY_V2|$BODY_V1\"; fi; fi"
        );
        string memory modeAndGuid = _bash(submitCmd);
        console.log("Explorer submit:", modeAndGuid);
    }

    function _bash(string memory fullCommand) internal returns (string memory) {
        string[] memory cmd = new string[](3);
        cmd[0] = "bash";
        cmd[1] = "-lc";
        cmd[2] = fullCommand;
        bytes memory out = vm.ffi(cmd);
        return string(out);
    }
}

