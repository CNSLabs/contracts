// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";

struct RolesConfig {
    address admin;
    address allowlistAdmin;
    address upgrader;
    address pauser;
}

struct ChainConfig {
    string name;
    uint256 chainId;
}

struct TimelockConfig {
    uint256 minDelay;
    address admin;
    address[] proposers;
    address[] executors;
    address addr; // optional: deployed timelock address
}

struct L1Config {
    string name;
    string symbol;
    uint8 decimals;
    uint256 initialSupply;
    address proxy; // optional: deployed proxy address
    address implementation; // optional: deployed implementation address
    RolesConfig roles;
    ChainConfig chain;
    TimelockConfig timelock;
}

struct EnvConfig {
    string env;
    L1Config l1;
}

library ConfigLoader {
    // Safe readers: return defaults when keys are missing
    function _readString(Vm vm_, string memory json, string memory key, string memory defaultValue)
        private
        pure
        returns (string memory)
    {
        try vm_.parseJson(json, key) returns (bytes memory raw) {
            if (raw.length == 0) return defaultValue;
            return abi.decode(raw, (string));
        } catch {
            return defaultValue;
        }
    }

    function _readUint(Vm vm_, string memory json, string memory key, uint256 defaultValue)
        private
        pure
        returns (uint256)
    {
        try vm_.parseJson(json, key) returns (bytes memory raw) {
            if (raw.length == 0) return defaultValue;
            return abi.decode(raw, (uint256));
        } catch {
            return defaultValue;
        }
    }

    function _readAddress(Vm vm_, string memory json, string memory key, address defaultValue)
        private
        pure
        returns (address)
    {
        try vm_.parseJsonAddress(json, key) returns (address parsed) {
            return parsed;
        } catch {
            return defaultValue;
        }
    }

    function _readAddressArray(Vm vm_, string memory json, string memory key) private pure returns (address[] memory) {
        try vm_.parseJson(json, key) returns (bytes memory raw) {
            if (raw.length == 0) return new address[](0);
            return abi.decode(raw, (address[]));
        } catch {
            return new address[](0);
        }
    }

    function loadFromPath(Vm vm_, string memory path) internal view returns (EnvConfig memory cfg) {
        string memory json = vm_.readFile(path);

        cfg.env = _readString(vm_, json, ".env", "");

        // L1
        cfg.l1.name = _readString(vm_, json, ".l1.name", "");
        cfg.l1.symbol = _readString(vm_, json, ".l1.symbol", "");
        cfg.l1.decimals = uint8(_readUint(vm_, json, ".l1.decimals", 18));
        cfg.l1.initialSupply = _readUint(vm_, json, ".l1.initialSupply", 0);
        cfg.l1.proxy = _readAddress(vm_, json, ".l1.proxy", address(0));
        cfg.l1.implementation = _readAddress(vm_, json, ".l1.implementation", address(0));
        cfg.l1.roles.admin = _readAddress(vm_, json, ".l1.roles.admin", address(0));
        cfg.l1.roles.allowlistAdmin = _readAddress(vm_, json, ".l1.roles.allowlistAdmin", address(0));
        cfg.l1.roles.upgrader = _readAddress(vm_, json, ".l1.roles.upgrader", address(0));
        cfg.l1.roles.pauser = _readAddress(vm_, json, ".l1.roles.pauser", address(0));
        cfg.l1.chain.name = _readString(vm_, json, ".l1.chain.name", "");
        cfg.l1.chain.chainId = _readUint(vm_, json, ".l1.chain.chainId", 0);

        // L1 Timelock (optional)
        cfg.l1.timelock.minDelay = _readUint(vm_, json, ".l1.timelock.minDelay", 0);
        cfg.l1.timelock.admin = _readAddress(vm_, json, ".l1.timelock.admin", address(0));
        cfg.l1.timelock.proposers = _readAddressArray(vm_, json, ".l1.timelock.proposers");
        cfg.l1.timelock.executors = _readAddressArray(vm_, json, ".l1.timelock.executors");
        cfg.l1.timelock.addr = _readAddress(vm_, json, ".l1.timelock.addr", address(0));
    }

    function loadEnv(Vm vm_, string memory envName) internal view returns (EnvConfig memory cfg) {
        string memory path = string.concat("config/", envName, ".json");
        return loadFromPath(vm_, path);
    }
}
