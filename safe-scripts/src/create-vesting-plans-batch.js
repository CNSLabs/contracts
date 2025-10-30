#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { Command } = require('commander');
const { ethers } = require('ethers');
const { TransactionGenerator } = require('./transaction-generator');
const { 
  loadConfig, 
  getValue, 
  validateAddress, 
  validateBigInt 
} = require('./utils');

// Load environment variables from project root
require('dotenv').config({ path: path.join(__dirname, '..', '..', '.env') });

const program = new Command();

program
  .name('create-vesting-plans-batch')
  .description('Generate vesting plans batch transaction for Hedgey')
  .version('1.0.0')
  .option('-e, --env <environment>', 'Environment (dev, alpha, production)', 'dev')
  .option('--testnet', 'Use testnet chain ID (59141), otherwise mainnet (59144)')
  .option('-o, --output <file>', 'Output file path', 'vesting-plans-batch.json')
  .option('--token-contract <address>', 'Token contract address (overrides config)')
  .option('--batch-planner <address>', 'Batch planner contract address (overrides config)')
  .option('--vesting-admin <address>', 'Vesting admin address (overrides config)')
  .option('--dry-run', 'Print the generated JSON without writing to file')
  .parse();

const options = program.opts();

// ERC20 approve ABI
const ERC20_APPROVE_ABI = [
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

// Hedgey Batch Planner ABI - batchVestingPlans only
const BATCH_PLANNER_ABI = [
  {
    "inputs": [
      {
        "internalType": "address",
        "name": "locker",
        "type": "address"
      },
      {
        "internalType": "address",
        "name": "token",
        "type": "address"
      },
      {
        "internalType": "uint256",
        "name": "totalAmount",
        "type": "uint256"
      },
      {
        "components": [
          {
            "internalType": "address",
            "name": "recipient",
            "type": "address"
          },
          {
            "internalType": "uint256",
            "name": "amount",
            "type": "uint256"
          },
          {
            "internalType": "uint256",
            "name": "start",
            "type": "uint256"
          },
          {
            "internalType": "uint256",
            "name": "cliff",
            "type": "uint256"
          },
          {
            "internalType": "uint256",
            "name": "rate",
            "type": "uint256"
          }
        ],
        "internalType": "struct IHedgeyBatchPlanner.Plan[]",
        "name": "plans",
        "type": "tuple[]"
      },
      {
        "internalType": "uint256",
        "name": "period",
        "type": "uint256"
      },
      {
        "internalType": "address",
        "name": "vestingAdmin",
        "type": "address"
      },
      {
        "internalType": "bool",
        "name": "adminTransferOBO",
        "type": "bool"
      },
      {
        "internalType": "uint8",
        "name": "mintType",
        "type": "uint8"
      }
    ],
    "name": "batchVestingPlans",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  }
];

/**
 * Normalize plan values to strings for BigInt safety
 * @param {Array} plans - Array of plan objects
 * @returns {Array} - Array of normalized plan objects
 */
function normalizePlans(plans) {
  return plans.map(plan => ({
    recipient: plan.recipient,
    amount: plan.amount.toString(),
    start: plan.start.toString(),
    cliff: plan.cliff.toString(),
    rate: plan.rate.toString()
  }));
}

/**
 * Validate vesting plan with consolidated logic
 * @param {Object} plan - Plan object to validate
 * @param {number} index - Plan index for error messages
 * @throws {Error} - If plan validation fails
 */
function validatePlan(plan, index) {
  const errors = [];
  const planPrefix = `Plan ${index + 1}`;
  
  // Validate recipient address
  if (!plan.recipient) {
    errors.push(`${planPrefix}: recipient is required`);
  } else if (!ethers.isAddress(plan.recipient)) {
    errors.push(`${planPrefix}: recipient must be a valid Ethereum address`);
  }
  
  // Validate numeric fields using helper
  const amountError = validateBigInt(plan.amount, 'amount');
  if (amountError) errors.push(`${planPrefix}: ${amountError}`);
  
  const startError = validateBigInt(plan.start, 'start timestamp');
  if (startError) errors.push(`${planPrefix}: ${startError}`);
  
  const cliffError = validateBigInt(plan.cliff, 'cliff timestamp');
  if (cliffError) errors.push(`${planPrefix}: ${cliffError}`);
  
  const rateError = validateBigInt(plan.rate, 'rate');
  if (rateError) errors.push(`${planPrefix}: ${rateError}`);
  
  // Validate start <= cliff
  if (plan.start && plan.cliff) {
    try {
      if (BigInt(plan.start) > BigInt(plan.cliff)) {
        errors.push(`${planPrefix}: start must be <= cliff`);
      }
    } catch (e) {
      // Already handled by individual field validation
    }
  }
  
  if (errors.length > 0) {
    throw new Error(`Plan validation failed:\n${errors.join('\n')}`);
  }
}

function generateVestingPlansBatch() {
  try {
    // Load configuration
    const config = loadConfig(options.env);
    console.log(`Loaded config for environment: ${options.env}`);
    
    // Determine chain ID based on testnet flag
    const chainId = options.testnet ? '59141' : '59144';
    console.log(`Using chain ID: ${chainId} (${options.testnet ? 'testnet' : 'mainnet'})`);
    
    // Get contract addresses
    const tokenContract = validateAddress(
      getValue(
        options.tokenContract,
        'SHO_TOKEN_L2_PROXY',
        'l2.proxy',
        config
      ),
      'Token contract'
    );
    
    const batchPlanner = validateAddress(
      getValue(
        options.batchPlanner,
        'HEDGEY_BATCH_PLANNER',
        'hedgey.batchPlanner',
        config
      ),
      'Batch planner contract'
    );
    
    const vestingAdmin = validateAddress(
      getValue(
        options.vestingAdmin,
        'HEDGEY_VESTING_ADMIN',
        'hedgey.vestingAdmin',
        config
      ),
      'Vesting admin'
    );
    
    const tokenVestingPlans = validateAddress(
      getValue(
        null,
        'HEDGEY_TOKEN_VESTING_PLANS',
        'hedgey.tokenVestingPlans',
        config
      ),
      'Token vesting plans contract'
    );
    
    // Get vesting plans from config
    const plans = config.hedgey.plans || [];
    if (plans.length === 0) {
      throw new Error('No vesting plans found in config. Please add plans to hedgey.plans array.');
    }
    
    // Validate all plans
    plans.forEach((plan, index) => validatePlan(plan, index));
    
    // Normalize plan amounts to strings and calculate total amount
    const normalizedPlans = normalizePlans(plans);
    
    // Calculate total amount
    const totalAmount = normalizedPlans.reduce((sum, plan) => sum + BigInt(plan.amount), 0n);
    
    // Get other parameters
    const period = config.hedgey.period || 1;
    const adminTransferOBO = config.hedgey.adminTransferOBO || false;
    const mintType = 0; // Default mint type
    
    // Create transaction generator
    const generator = new TransactionGenerator();
    
    // Add approve transaction
    generator.addContractCall(
      tokenContract,
      'approve',
      [batchPlanner, totalAmount.toString()],
      ERC20_APPROVE_ABI
    );
    
    // Add batch vesting plans transaction
    generator.addContractCall(
      batchPlanner,
      'batchVestingPlans',
      [
        tokenVestingPlans, // locker
        tokenContract,
        totalAmount.toString(),
        normalizedPlans, // plans array with normalized values
        period,
        vestingAdmin, // vestingAdmin
        adminTransferOBO,
        mintType
      ],
      BATCH_PLANNER_ABI
    );
    
    // Validate transactions
    generator.validate();
    
    // Display configuration summary
    console.log('\nConfiguration Summary:');
    console.log(`Environment: ${options.env}`);
    console.log(`Chain ID: ${chainId} (${options.testnet ? 'testnet' : 'mainnet'})`);
    console.log(`Token Contract: ${tokenContract}`);
    console.log(`Batch Planner: ${batchPlanner}`);
    console.log(`Token Vesting Plans: ${tokenVestingPlans}`);
    console.log(`Vesting Admin: ${vestingAdmin}`);
    console.log(`Number of Plans: ${plans.length}`);
    console.log(`Total Amount: ${totalAmount.toString()}`);
    console.log(`Period: ${period}`);
    console.log(`Admin Transfer OBO: ${adminTransferOBO}`);
    
    console.log('\nPlans:');
    plans.forEach((plan, index) => {
      console.log(`  Plan ${index + 1}: ${plan.recipient} - ${plan.amount} tokens`);
    });
    
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
      const output = generator.generateBatch(vestingAdmin, chainId);
      
      fs.writeFileSync(outputPath, output);
      console.log(`\nVesting plans batch written to: ${outputPath}`);
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

generateVestingPlansBatch();
