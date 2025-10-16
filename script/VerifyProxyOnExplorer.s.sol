// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./BaseScript.sol";

/**
 * @title VerifyProxyOnExplorer
 * @notice Standalone script to mark an already-deployed proxy as a proxy on LineaScan (Etherscan v2)
 * @dev Requires FFI enabled (FOUNDRY_FFI=1), and tools curl + jq available
 *
 * Usage examples:
 *   PROXY_ADDRESS=0x... LINEA_ETHERSCAN_API_KEY=... forge script script/VerifyProxyOnExplorer.s.sol:VerifyProxyOnExplorer --rpc-url linea_sepolia --broadcast
 *   # Optional overrides:
 *   LINEA_VERIFIER_URL=https://api-sepolia.lineascan.build/v2/api
 */
contract VerifyProxyOnExplorer is BaseScript {
    // EIP-1967 implementation slot: bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
    bytes32 constant EIP1967_IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function run() external {
        address proxyAddr = _readProxyAddress();
        address implAddr = _loadImplementation(proxyAddr);

        console.log("Proxy:", proxyAddr);
        console.log("Implementation (from EIP-1967):", implAddr);

        _markProxyOnExplorer(proxyAddr, implAddr);
    }

    function _readProxyAddress() internal view returns (address) {
        // Default to provided address if env not set
        string memory addrStr = vm.envOr("PROXY_ADDRESS", string("0x8b4f9a5B10421416726908b882b35910D41B757c"));
        return vm.parseAddress(addrStr);
    }

    function _loadImplementation(address proxyAddr) internal view returns (address) {
        bytes32 raw = vm.load(proxyAddr, EIP1967_IMPL_SLOT);
        return address(uint160(uint256(raw)));
    }

    function _markProxyOnExplorer(address proxyAddr, address implAddr) internal {
        // Only attempt on Linea networks
        if (block.chainid != LINEA_SEPOLIA && block.chainid != LINEA_MAINNET) {
            console.log("[INFO] Not on Linea network; skipping explorer call");
            return;
        }

        string memory apiKey = vm.envOr("LINEA_ETHERSCAN_API_KEY", string(""));
        if (bytes(apiKey).length == 0) {
            console.log("[ERROR] LINEA_ETHERSCAN_API_KEY is required");
            return;
        }

        // Compute v2 and v1 base URLs
        string memory defaultUrlV2 = block.chainid == LINEA_MAINNET
            ? "https://api.lineascan.build/v2/api"
            : "https://api-sepolia.lineascan.build/v2/api";
        string memory defaultUrlV1 = block.chainid == LINEA_MAINNET
            ? "https://api.lineascan.build/api"
            : "https://api-sepolia.lineascan.build/api";
        string memory urlV2 = vm.envOr("LINEA_VERIFIER_URL", defaultUrlV2);
        string memory urlV1 = vm.envOr("LINEA_VERIFIER_URL_V1", defaultUrlV1);

        console.log("Explorer API v2:", urlV2);
        console.log("Explorer API v1:", urlV1);

        // Submit verifyproxycontract: try v2 first (header key), then v1 (apikey param) on failure
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
            // Success if we got a GUID or an explicit success code
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
        console.log("Submit result:", modeAndGuid);

        // Fail fast on known deprecation response from v1
        if (_contains(modeAndGuid, "deprecated V1 endpoint")) {
            console.log("[ERROR] Explorer v1 endpoint deprecated and v2 likely unavailable on this network");
            console.log("        Please try again later or use manual UI until LineaScan v2 supports this action.");
            return;
        }

        // If it looks like Already Verified, we're done
        if (_contains(modeAndGuid, "Already Verified")) {
            console.log("[OK] Proxy already marked as verified on explorer");
            return;
        }

        // Must have MODE|GUID
        if (!_contains(modeAndGuid, "|")) {
            console.log("[WARN] Submit did not return MODE|GUID; aborting");
            return;
        }

        // Poll status
        for (uint256 i = 0; i < 3; i++) {
            string memory checkCmd = string.concat(
                "MODE_GUID=\"",
                modeAndGuid,
                "\"; ",
                "MODE=${MODE_GUID%%|*}; GUID=${MODE_GUID#*|}; ",
                "if [[ \"$MODE\" == \"v2\" ]]; then ",
                "RESP=$(curl -s -G ",
                urlV2,
                " -H 'User-Agent: foundry-ffi/1.0' -H 'Accept: application/json' -H 'X-Api-Key: ",
                apiKey,
                "'",
                " --data-urlencode chainid=",
                vm.toString(block.chainid),
                " --data-urlencode module=contract",
                " --data-urlencode action=checkproxyverification",
                " --data-urlencode guid=$GUID); ",
                "else ",
                "RESP=$(curl -s -G ",
                urlV1,
                " -H 'User-Agent: foundry-ffi/1.0' -H 'Accept: application/json'",
                " --data-urlencode module=contract",
                " --data-urlencode action=checkproxyverification",
                " --data-urlencode guid=$GUID",
                " --data-urlencode apikey=",
                apiKey,
                "); fi; ",
                "echo \"$RESP\" | jq -r '((.status // .code // \"\") + \"|\" + (.result // .message // .data // \"\"))' 2>/dev/null || echo \"$RESP\""
            );
            string memory statusLine = _bash(checkCmd);
            console.log("Check:", statusLine);

            if (_contains(statusLine, "1|") || _contains(statusLine, "Already Verified")) {
                console.log("[OK] Proxy marked as verified on explorer");
                break;
            }
            if (_contains(statusLine, "Fail")) {
                console.log("[WARN] Proxy verification failed on explorer");
                break;
            }
            _sleep(4);
        }
    }

    function _bash(string memory commandLine) internal returns (string memory) {
        string[] memory cmd = new string[](3);
        cmd[0] = "bash";
        cmd[1] = "-lc";
        cmd[2] = commandLine;
        bytes memory out = vm.ffi(cmd);
        return string(out);
    }

    function _sleep(uint256 seconds_) internal {
        string[] memory cmd = new string[](3);
        cmd[0] = "bash";
        cmd[1] = "-lc";
        cmd[2] = string.concat("sleep ", vm.toString(seconds_));
        vm.ffi(cmd);
    }

    function _contains(string memory s, string memory needle) internal pure returns (bool) {
        bytes memory a = bytes(s);
        bytes memory b = bytes(needle);
        if (b.length == 0) return true;
        if (b.length > a.length) return false;
        for (uint256 i = 0; i <= a.length - b.length; i++) {
            bool matched = true;
            for (uint256 j = 0; j < b.length; j++) {
                if (a[i + j] != b[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) return true;
        }
        return false;
    }
}
