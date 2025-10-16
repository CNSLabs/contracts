// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

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

struct L1Config {
    string name;
    string symbol;
    uint8 decimals;
    uint256 initialSupply;
    RolesConfig roles;
    ChainConfig chain;
}

struct L2Config {
    string name;
    string symbol;
    uint8 decimals;
    address bridge;
    address l1Token;
    address proxy;
    RolesConfig roles;
    ChainConfig chain;
}

struct HedgeyConfig {
    address investorLockup;
    address batchPlanner;
    address recipient;
    uint256 amount;
    uint256 start;
    uint256 cliff;
    uint256 rate;
    uint256 period;
}

struct EnvConfig {
    string env;
    L1Config l1;
    L2Config l2;
    HedgeyConfig hedgey;
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
        try vm_.parseJson(json, key) returns (bytes memory raw) {
            if (raw.length == 0) return defaultValue;
            return abi.decode(raw, (address));
        } catch {
            return defaultValue;
        }
    }

    function loadFromPath(Vm vm_, string memory path)
        internal
        view
        returns (EnvConfig memory cfg)
    {
        string memory json = vm_.readFile(path);

        cfg.env = _readString(vm_, json, ".env", "");

        // L1
        cfg.l1.name = _readString(vm_, json, ".l1.name", "");
        cfg.l1.symbol = _readString(vm_, json, ".l1.symbol", "");
        cfg.l1.decimals = uint8(_readUint(vm_, json, ".l1.decimals", 18));
        cfg.l1.initialSupply = _readUint(vm_, json, ".l1.initialSupply", 0);
        cfg.l1.roles.admin = _readAddress(vm_, json, ".l1.roles.admin", address(0));
        cfg.l1.roles.allowlistAdmin = _readAddress(vm_, json, ".l1.roles.allowlistAdmin", address(0));
        cfg.l1.roles.upgrader = _readAddress(vm_, json, ".l1.roles.upgrader", address(0));
        cfg.l1.roles.pauser = _readAddress(vm_, json, ".l1.roles.pauser", address(0));
        cfg.l1.chain.name = _readString(vm_, json, ".l1.chain.name", "");
        cfg.l1.chain.chainId = _readUint(vm_, json, ".l1.chain.chainId", 0);

        // L2
        cfg.l2.name = _readString(vm_, json, ".l2.name", "");
        cfg.l2.symbol = _readString(vm_, json, ".l2.symbol", "");
        cfg.l2.decimals = uint8(_readUint(vm_, json, ".l2.decimals", 18));
        cfg.l2.bridge = _readAddress(vm_, json, ".l2.bridge", address(0));
        cfg.l2.l1Token = _readAddress(vm_, json, ".l2.l1Token", address(0));
        cfg.l2.proxy = _readAddress(vm_, json, ".l2.proxy", address(0));
        cfg.l2.roles.admin = _readAddress(vm_, json, ".l2.roles.admin", address(0));
        cfg.l2.roles.allowlistAdmin = _readAddress(vm_, json, ".l2.roles.allowlistAdmin", address(0));
        cfg.l2.roles.upgrader = _readAddress(vm_, json, ".l2.roles.upgrader", address(0));
        cfg.l2.roles.pauser = _readAddress(vm_, json, ".l2.roles.pauser", address(0));
        cfg.l2.chain.name = _readString(vm_, json, ".l2.chain.name", "");
        cfg.l2.chain.chainId = _readUint(vm_, json, ".l2.chain.chainId", 0);

        // Hedgey (optional)
        cfg.hedgey.investorLockup = _readAddress(vm_, json, ".hedgey.investorLockup", address(0));
        cfg.hedgey.batchPlanner = _readAddress(vm_, json, ".hedgey.batchPlanner", address(0));
        cfg.hedgey.recipient = _readAddress(vm_, json, ".hedgey.recipient", address(0));
        cfg.hedgey.amount = _readUint(vm_, json, ".hedgey.amount", 0);
        cfg.hedgey.start = _readUint(vm_, json, ".hedgey.start", 0);
        cfg.hedgey.cliff = _readUint(vm_, json, ".hedgey.cliff", 0);
        cfg.hedgey.rate = _readUint(vm_, json, ".hedgey.rate", 0);
        cfg.hedgey.period = _readUint(vm_, json, ".hedgey.period", 0);
    }

    function loadEnv(Vm vm_, string memory envName)
        internal
        view
        returns (EnvConfig memory cfg)
    {
        string memory path = string.concat("config/", envName, ".json");
        return loadFromPath(vm_, path);
    }
}


