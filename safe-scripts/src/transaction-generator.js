const { ethers } = require('ethers');
const { TxBuilder } = require("@morpho-labs/gnosis-tx-builder");

/**
 * Base library for generating transaction arrays and calldata
 */
class TransactionGenerator {
  constructor() {
    this.transactions = [];
  }

  /**
   * Add an ETH transfer transaction
   * @param {string} to - Recipient address
   * @param {string|number} amount - Amount in ETH (will be converted to wei)
   * @returns {TransactionGenerator} - For method chaining
   */
  addEthTransfer(to, amount) {
    const value = ethers.parseEther(amount.toString()).toString();
    this.transactions.push({
      to,
      value,
      data: "0x"
    });
    return this;
  }

  /**
   * Add a contract call transaction
   * @param {string} to - Contract address
   * @param {string} method - Method name
   * @param {Array} args - Method arguments
   * @param {Array} abi - Contract ABI (can be full ABI or just the method)
   * @param {string|number} value - ETH value to send (default: 0)
   * @returns {TransactionGenerator} - For method chaining
   */
  addContractCall(to, method, args = [], abi, value = 0) {
    const iface = new ethers.Interface(abi);
    const calldata = iface.encodeFunctionData(method, args);
    
    this.transactions.push({
      to,
      value: value.toString(),
      data: calldata
    });
    return this;
  }

  /**
   * Add a raw call transaction
   * @param {string} to - Contract address
   * @param {string} data - Raw calldata
   * @param {string|number} value - ETH value to send (default: 0)
   * @returns {TransactionGenerator} - For method chaining
   */
  addRawCall(to, data, value = 0) {
    this.transactions.push({
      to,
      value: value.toString(),
      data
    });
    return this;
  }

  /**
   * Get the current transactions array
   * @returns {Array} - Array of transaction objects
   */
  getTransactions() {
    return this.transactions;
  }

  /**
   * Generate JavaScript code for the transactions array
   * @param {string} variableName - Name of the variable (default: 'transactions')
   * @returns {string} - JavaScript code string
   */
  toJavaScript(variableName = 'transactions') {
    return `const ${variableName} = ${JSON.stringify(this.transactions, null, 2)};`;
  }

  /**
   * Generate JSON string for the transactions array
   * @returns {string} - JSON string
   */
  toJSON() {
    return JSON.stringify(this.transactions, null, 2);
  }

  /**
   * Clear all transactions
   * @returns {TransactionGenerator} - For method chaining
   */
  clear() {
    this.transactions = [];
    return this;
  }

  /**
   * Get transaction count
   * @returns {number} - Number of transactions
   */
  count() {
    return this.transactions.length;
  }

  /**
   * Validate all transactions
   * @throws {Error} - If any transaction is invalid
   */
  validate() {
    for (let i = 0; i < this.transactions.length; i++) {
      const tx = this.transactions[i];
      
      if (!tx.to) {
        throw new Error(`Transaction ${i + 1}: 'to' address is required`);
      }
      
      if (!ethers.isAddress(tx.to)) {
        throw new Error(`Transaction ${i + 1}: 'to' must be a valid Ethereum address`);
      }
      
      if (tx.value === undefined || tx.value === null) {
        throw new Error(`Transaction ${i + 1}: 'value' is required`);
      }
      
      if (tx.data === undefined || tx.data === null) {
        throw new Error(`Transaction ${i + 1}: 'data' is required`);
      }
    }
  }
  
  /**
   * Generate a transaction batch
   * @param {string} safeAddress - Safe address
   * @param {string} chainId - Chain ID
   * @returns {string} - Transaction batch as a JSON string
   */
  generateBatch(safeAddress, chainId) {
    return JSON.stringify(TxBuilder.batch(safeAddress, this.transactions, { chainId }), null, 2);
  }
}

module.exports = {
  TransactionGenerator,
};
