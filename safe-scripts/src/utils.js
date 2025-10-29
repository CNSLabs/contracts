const fs = require('fs');
const path = require('path');
const { ethers } = require('ethers');

/**
 * Load configuration from environment-specific JSON file
 * @param {string} env - Environment name (dev, alpha, production)
 * @returns {Object} - Parsed configuration object
 */
function loadConfig(env) {
  const configPath = path.join(__dirname, '..', '..', 'config', `${env}.json`);
  
  if (!fs.existsSync(configPath)) {
    throw new Error(`Config file not found: ${configPath}`);
  }
  
  const configContent = fs.readFileSync(configPath, 'utf8');
  return JSON.parse(configContent);
}

/**
 * Get value with priority: CLI override > Environment variable > Config file
 * @param {*} override - CLI override value
 * @param {string} envVar - Environment variable name
 * @param {string} configPath - Config file path (dot notation)
 * @param {Object} config - Configuration object
 * @returns {*} - Resolved value
 */
function getValue(override, envVar, configPath, config) {
  // Priority: CLI override > Environment variable > Config file
  if (override) {
    return override;
  }
  
  if (envVar && process.env[envVar]) {
    return process.env[envVar];
  }
  
  if (configPath) {
    const keys = configPath.split('.');
    let value = config;
    for (const key of keys) {
      if (value && typeof value === 'object' && key in value) {
        value = value[key];
      } else {
        return null;
      }
    }
    return value;
  }
  
  return null;
}

/**
 * Validate Ethereum address using ethers.isAddress
 * @param {string} address - Address to validate
 * @param {string} name - Field name for error messages
 * @param {boolean} allowZero - Allow zero address
 * @returns {string} - Validated address
 * @throws {Error} - If address is invalid
 */
function validateAddress(address, name, allowZero = false) {
  if (!address) {
    throw new Error(`${name} address is required`);
  }
  
  if (allowZero && address === '0x0000000000000000000000000000000000000000') {
    return address;
  }
  
  if (!ethers.isAddress(address)) {
    throw new Error(`${name} address must be a valid Ethereum address (0x...)`);
  }
  
  return address;
}

/**
 * Validate and convert BigInt values safely
 * @param {*} value - Value to validate
 * @param {string} fieldName - Field name for error messages
 * @returns {string|null} - Error message or null if valid
 */
function validateBigInt(value, fieldName) {
  if (!value) {
    return `${fieldName} is required`;
  }
  
  try {
    const bigValue = BigInt(value);
    if (bigValue <= 0n) {
      return `${fieldName} must be greater than 0`;
    }
    return null; // Valid
  } catch (e) {
    return `${fieldName} must be a valid number`;
  }
}

/**
 * Validate token supply amount with BigInt conversion
 * @param {*} supply - Supply amount to validate
 * @param {string} name - Field name for error messages
 * @returns {string} - Validated amount as string
 * @throws {Error} - If supply is invalid
 */
function validateTokenSupply(supply, name) {
  if (!supply) {
    throw new Error(`${name} token supply is required`);
  }
  
  let amount;
  
  // Handle different input types
  if (typeof supply === 'string') {
    amount = BigInt(supply);
  } else if (typeof supply === 'number') {
    let supplyStr = supply.toString();
    if (supplyStr.includes('e') || supplyStr.includes('E')) {
      supplyStr = supply.toLocaleString('fullwide', {useGrouping: false});
    }
    amount = BigInt(supplyStr);
  } else {
    amount = BigInt(supply.toString());
  }
  
  if (amount <= 0n) {
    throw new Error(`${name} token supply must be greater than 0`);
  }
  
  return amount.toString();
}

module.exports = {
  loadConfig,
  getValue,
  validateAddress,
  validateBigInt,
  validateTokenSupply
};
