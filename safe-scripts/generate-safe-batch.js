#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { Command } = require('commander');

// Load environment variables from project root
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const program = new Command();

program
  .name('generate-safe-batch')
  .description('Generate Safe transaction batch JSON from template with config substitution')
  .version('1.0.0')
  .option('-e, --env <environment>', 'Environment (dev, alpha, production)', 'dev')
  .option('--testnet', 'Use testnet chain ID (11155111), otherwise use mainnet (1)')
  .option('-o, --output <file>', 'Output file path', 'safe-batch.json')
  .option('--token-holder <address>', 'Token holder safe address (overrides config)')
  .option('--token-contract <address>', 'Token contract address (overrides config)')
  .option('--token-supply <amount>', 'Token supply amount (overrides config)')
  .option('--bridge-contract <address>', 'Bridge contract address (overrides config)')
  .option('--recipient <address>', 'Recipient address for bridged tokens (overrides config)')
  .option('--dry-run', 'Print the generated JSON without writing to file')
  .parse();

const options = program.opts();

// Template JSON
const template = {
  "version": "1.0",
  "chainId": "{ChainID}",
  "createdAt": Date.now(),
  "meta": {
    "name": "Transactions Batch",
    "description": "",
    "txBuilderVersion": "1.18.2",
    "createdFromSafeAddress": "{TokenHolderSafe}",
    "createdFromOwnerAddress": "",
    "checksum": ""
  },
  "transactions": [
    {
      "to": "{TokenContract}",
      "value": "0",
      "data": null,
      "contractMethod": {
        "inputs": [
          {
            "internalType": "address",
            "name": "spender",
            "type": "address"
          },
          {
            "internalType": "uint256",
            "name": "value",
            "type": "uint256"
          }
        ],
        "name": "approve",
        "payable": false
      },
      "contractInputsValues": {
        "spender": "{BridgeContract}",
        "value": "{TokenSupply}"
      }
    },
    {
      "to": "{BridgeContract}",
      "value": "0",
      "data": null,
      "contractMethod": {
        "inputs": [
          {
            "internalType": "address",
            "name": "_token",
            "type": "address"
          },
          {
            "internalType": "uint256",
            "name": "_amount",
            "type": "uint256"
          },
          {
            "internalType": "address",
            "name": "_recipient",
            "type": "address"
          }
        ],
        "name": "bridgeToken",
        "payable": true
      },
      "contractInputsValues": {
        "_token": "{TokenContract}",
        "_amount": "{TokenSupply}",
        "_recipient": "{Recipient}"
      }
    }
  ]
};

function loadConfig(env) {
  const configPath = path.join(__dirname, '..', 'config', `${env}.json`);
  
  if (!fs.existsSync(configPath)) {
    throw new Error(`Config file not found: ${configPath}`);
  }
  
  const configContent = fs.readFileSync(configPath, 'utf8');
  return JSON.parse(configContent);
}

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

function validateAddress(address, name, allowZero = false) {
  if (!address) {
    throw new Error(`${name} address is required`);
  }
  
  if (allowZero && address === '0x0000000000000000000000000000000000000000') {
    return address;
  }
  
  if (!/^0x[a-fA-F0-9]{40}$/.test(address)) {
    throw new Error(`${name} address must be a valid Ethereum address (0x...)`);
  }
  
  return address;
}

function validateTokenSupply(supply, name) {
  if (!supply) {
    throw new Error(`${name} token supply is required`);
  }
  
  let amount;
  
  // Handle different input types
  if (typeof supply === 'string') {
    // If it's already a string, use it directly
    amount = BigInt(supply);
  } else if (typeof supply === 'number') {
    // For very large numbers, we need to handle scientific notation
    // Convert to string and check if it contains 'e'
    let supplyStr = supply.toString();
    if (supplyStr.includes('e') || supplyStr.includes('E')) {
      // Use Number.toLocaleString('fullwide', {useGrouping: false}) to avoid scientific notation
      supplyStr = supply.toLocaleString('fullwide', {useGrouping: false});
    }
    amount = BigInt(supplyStr);
  } else {
    // For other types, convert to string first
    amount = BigInt(supply.toString());
  }
  
  if (amount <= 0n) {
    throw new Error(`${name} token supply must be greater than 0`);
  }
  
  return amount.toString();
}

function generateBatch() {
  try {
    // Load configuration
    const config = loadConfig(options.env);
    console.log(`Loaded config for environment: ${options.env}`);
    
    // Determine chain ID based on testnet flag
    const chainId = options.testnet ? '11155111' : '1';
    console.log(`Using chain ID: ${chainId} (${options.testnet ? 'testnet' : 'mainnet'})`);
    
    
    const tokenHolderSafe = validateAddress(
      getValue(
        options.tokenHolder,
        'SHO_DEFAULT_ADMIN',
        `l1.roles.admin`,
        config
      ),
      'Token holder safe'
    );
    
    const tokenContractValue = getValue(
      options.tokenContract,
      'SHO_TOKEN_L1', // Always L2 proxy since we're dealing with L2 chains
      'l2.l1Token',
      config
    );
    
    if (!tokenContractValue) {
      throw new Error(
        `Token contract address not found. Please provide it via:\n` +
        `  - Command line: --token-contract <address>\n` +
        `  - Environment variable: SHO_TOKEN_L2_PROXY\n` +
        `  - Config file: l2.proxy`
      );
    }
    
    const tokenContract = validateAddress(
      tokenContractValue,
      'Token contract'
    );
    
    const tokenSupply = validateTokenSupply(
      getValue(
        options.tokenSupply,
        null,
        'l1.initialSupply',
        config
      ),
      'Token'
    );

    // Get recipient address - default to l2.roles.admin, fallback to token holder safe
    const recipientValue = getValue(
      options.recipient,
      null,
      'l2.roles.admin',
      config
    );
    
    const recipient = validateAddress(
      recipientValue || tokenHolderSafe, // Fallback to token holder safe if l2.roles.admin is not set
      'Recipient'
    );
    
    const bridgeContract = options.testnet ? '0x5A0a48389BB0f12E5e017116c1105da97E129142' : '0xd19d4B5d358258f05D7B411E21A1460D11B0876F';
    
    // Create a deep copy of the template
    const batch = JSON.parse(JSON.stringify(template));
    
    // Substitute placeholders
    const substitutions = {
      '{ChainID}': chainId,
      '{TokenHolderSafe}': tokenHolderSafe,
      '{TokenContract}': tokenContract,
      '{TokenSupply}': tokenSupply,
      '{BridgeContract}': bridgeContract,
      '{Recipient}': recipient
    };
    
    // Replace all placeholders in the JSON string
    let jsonString = JSON.stringify(batch, null, 2);
    for (const [placeholder, value] of Object.entries(substitutions)) {
      jsonString = jsonString.replace(new RegExp(placeholder.replace(/[{}]/g, '\\$&'), 'g'), value);
    }
    
    const result = JSON.parse(jsonString);
    
    // Display configuration summary
    console.log('\nConfiguration Summary:');
    console.log(`Environment: ${options.env}`);
    console.log(`Chain Type: L2 (Linea)`);
    console.log(`Chain ID: ${chainId} (${options.testnet ? 'testnet' : 'mainnet'})`);
    console.log(`Token Holder Safe: ${tokenHolderSafe}`);
    console.log(`Token Contract: ${tokenContract}`);
    console.log(`Token Supply: ${tokenSupply}`);
    console.log(`Bridge Contract: ${bridgeContract}`);
    console.log(`Recipient: ${recipient}`);
    
    if (options.dryRun) {
      console.log('\nGenerated JSON (dry run):');
      console.log(JSON.stringify(result, null, 2));
    } else {
      // Create out directory if it doesn't exist
      const outDir = path.join(__dirname, 'out');
      if (!fs.existsSync(outDir)) {
        fs.mkdirSync(outDir, { recursive: true });
      }
      
      // Write to file in out directory
      const outputPath = path.resolve(outDir, options.output);
      fs.writeFileSync(outputPath, JSON.stringify(result, null, 2));
      console.log(`\nSafe batch JSON written to: ${outputPath}`);
    }
    
  } catch (error) {
    console.error('Error:', error.message);
    process.exit(1);
  }
}

// Check if required dependencies are available
try {
  require('commander');
  require('dotenv');
} catch (error) {
  console.error('Missing required dependencies. Please install them with:');
  console.error('npm install commander dotenv');
  process.exit(1);
}

generateBatch();
