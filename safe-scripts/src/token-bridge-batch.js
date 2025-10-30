#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { Command } = require('commander');
const { TransactionGenerator } = require('./transaction-generator');
const { 
  loadConfig, 
  getValue, 
  validateAddress, 
  validateTokenSupply 
} = require('./utils');

// Load environment variables from project root
require('dotenv').config({ path: path.join(__dirname, '..', '..', '.env') });

const program = new Command();

program
  .name('token-bridge-batch')
  .description('Generate token bridge transaction batch (approve + bridgeToken)')
  .version('1.0.0')
  .option('-e, --env <environment>', 'Environment (dev, alpha, production)', 'dev')
  .option('--testnet', 'Use testnet chain ID (11155111), otherwise use mainnet (1)')
  .option('-o, --output <file>', 'Output file path', 'token-bridge-batch.json')
  .option('--token-holder <address>', 'Token holder safe address (overrides config)')
  .option('--token-contract <address>', 'Token contract address (overrides config)')
  .option('--token-supply <amount>', 'Token supply amount (overrides config)')
  .option('--bridge-contract <address>', 'Bridge contract address (overrides config)')
  .option('--recipient <address>', 'Recipient address for bridged tokens (overrides config)')
  .option('--dry-run', 'Print the generated transactions without writing to file')
  .parse();

const options = program.opts();

// Token ABI (ERC20 with ERC20Permit)
const TOKEN_ABI = [
  {
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
    "outputs": [
      {
        "internalType": "bool",
        "name": "",
        "type": "bool"
      }
    ],
    "stateMutability": "nonpayable",
    "type": "function"
  }
];

// Bridge contract ABI - bridgeToken function
const BRIDGE_ABI = [
  {
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
    "outputs": [],
    "stateMutability": "payable",
    "type": "function"
  }
];


function generateBridgeBatch() {
  try {
    // Load configuration
    const config = loadConfig(options.env);
    console.log(`Loaded config for environment: ${options.env}`);
    
    // Determine chain ID based on testnet flag
    const chainId = options.testnet ? '11155111' : '1';
    console.log(`Using chain ID: ${chainId} (${options.testnet ? 'testnet' : 'mainnet'})`);
    
    // Get token holder safe address
    const tokenHolderSafe = validateAddress(
      getValue(
        options.tokenHolder,
        'SHO_DEFAULT_ADMIN',
        `l1.roles.admin`,
        config
      ),
      'Token holder safe'
    );
    
    // Get token contract address
    const tokenContractValue = getValue(
      options.tokenContract,
      'SHO_TOKEN_L1',
      'l2.l1Token',
      config
    );
    
    if (!tokenContractValue) {
      throw new Error(
        `Token contract address not found. Please provide it via:\n` +
        `  - Command line: --token-contract <address>\n` +
        `  - Config file: l2.l1Token`
      );
    }
    
    const tokenContract = validateAddress(
      tokenContractValue,
      'Token contract'
    );
    
    // Get token supply
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
      recipientValue || tokenHolderSafe,
      'Recipient'
    );
    
    // Get the L1 bridge contract address
    const bridgeContract = options.bridgeContract || 
      (options.testnet ? '0x5A0a48389BB0f12E5e017116c1105da97E129142' : '0x051F1D88f0aF5763fB888eC4378b4D8B29ea3319');
    
    // Create transaction generator
    const generator = new TransactionGenerator();
    
    // Add approve transaction
    generator.addContractCall(
      tokenContract,
      'approve',
      [bridgeContract, tokenSupply],
      TOKEN_ABI
    );
    
    // Add bridge transaction
    generator.addContractCall(
      bridgeContract,
      'bridgeToken',
      [tokenContract, tokenSupply, recipient],
      BRIDGE_ABI
    );
    
    // Validate transactions
    generator.validate();
    
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
    console.log(`Number of Transactions: ${generator.count()}`);
    
    if (options.dryRun) {
      console.log('\nGenerated Transactions:');
      console.log(generator.toJavaScript());
    } else {
      // Create out directory if it doesn't exist
      const outDir = path.join(__dirname, 'out');
      if (!fs.existsSync(outDir)) {
        fs.mkdirSync(outDir, { recursive: true });
      }
      
      // Write to file
      const outputPath = path.resolve(outDir, options.output);
      console.log(outputPath, outDir, options.output);
      const output = generator.generateBatch(tokenHolderSafe, chainId);
      
      fs.writeFileSync(outputPath, output);
      console.log(`\nToken bridge batch written to: ${outputPath}`);
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
  require('ethers');
} catch (error) {
  console.error('Missing required dependencies. Please install them with:');
  console.error('npm install commander dotenv ethers');
  process.exit(1);
}

generateBridgeBatch();
