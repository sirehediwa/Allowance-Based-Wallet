# 💰 Allowance-Based Wallet

A smart contract-based wallet system built on Stacks that implements access control and approve/transferFrom functionality, similar to ERC-20 token standards but for STX wallet management.

## 🚀 Features

- 🏦 **Personal Wallet Management**: Create and manage your own STX wallet
- 💸 **Deposit & Withdraw**: Securely deposit and withdraw STX tokens
- 🤝 **Allowance System**: Approve others to spend STX on your behalf
- 🔄 **Transfer From**: Execute transfers using approved allowances
- 📊 **Transaction Tracking**: Monitor deposits, withdrawals, and approvals
- 🔒 **Access Control**: Wallet activation/deactivation for security
- 📈 **Metadata Tracking**: Track total deposited, withdrawn, and approved amounts

## 🛠️ Core Functions

### Wallet Management
- `create-wallet()` - Create a new wallet
- `deposit(amount)` - Deposit STX to your wallet
- `withdraw(amount)` - Withdraw STX from your wallet
- `emergency-withdraw-all()` - Withdraw all funds at once

### Allowance System
- `approve(spender, amount)` - Approve someone to spend on your behalf
- `transfer-from(owner, recipient, amount)` - Transfer using approved allowance
- `increase-allowance(spender, added-value)` - Increase existing allowance
- `decrease-allowance(spender, subtracted-value)` - Decrease existing allowance

### Security Controls
- `deactivate-wallet()` - Temporarily disable wallet operations
- `reactivate-wallet()` - Re-enable wallet operations

### Read Functions
- `get-wallet-balance(owner)` - Check wallet balance
- `get-allowance(owner, spender)` - Check approved allowance
- `get-wallet-info(owner)` - Get complete wallet information
- `get-wallet-metadata(owner)` - Get transaction statistics
- `is-wallet-active(owner)` - Check if wallet is active

## 📋 Usage Examples

### 1. Creating and Using a Basic Wallet
```clarity
;; Create your wallet
(contract-call? .allowance-based-wallet create-wallet)

;; Deposit 1000 STX
(contract-call? .allowance-based-wallet deposit u1000000000)

;; Check your balance
(contract-call? .allowance-based-wallet get-wallet-balance tx-sender)

;; Withdraw 500 STX
(contract-call? .allowance-based-wallet withdraw u500000000)
```

### 2. Using the Allowance System
```clarity
;; Approve Alice to spend 200 STX on your behalf
(contract-call? .allowance-based-wallet approve 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM u200000000)

;; Alice can now transfer STX from your wallet to Bob
(contract-call? .allowance-based-wallet transfer-from 
  'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG  ;; your address
  'ST2JHG361ZXG51QTKY2NQCVBPPRRE2KZB1HR05NNC  ;; Bob's address
  u100000000)                                     ;; 100 STX
```

### 3. Managing Allowances
```clarity
;; Check how much Alice can spend
(contract-call? .allowance-based-wallet get-allowance 
  tx-sender 
  'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)

;; Increase Alice's allowance by 50 STX
(contract-call? .allowance-based-wallet increase-allowance 
  'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM 
  u50000000)

;; Decrease Alice's allowance by 25 STX
(contract-call? .allowance-based-wallet decrease-allowance 
  'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM 
  u25000000)
```

## 🔧 Development Setup

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Basic understanding of Clarity smart contracts

### Installation
1. Clone this repository
2. Navigate to the project directory
3. Run Clarinet commands

### Testing
```bash
# Check contract syntax
clarinet check

# Run tests (if any)
clarinet test

# Deploy to testnet
clarinet deploy --testnet
```

## 🔐 Security Features

- ✅ **Access Control**: Only wallet owners can withdraw their funds
- ✅ **Allowance Validation**: Transfers cannot exceed approved amounts
- ✅ **Balance Verification**: Prevents overdrafts
- ✅ **Self-Approval Protection**: Users cannot approve themselves
- ✅ **Wallet State Management**: Ability to deactivate/reactivate wallets
- ✅ **Amount Validation**: Prevents zero or negative amount operations

## 💡 Use Cases

1. **💳 Shared Expense Management**: Approve family members to spend from a shared wallet
2. **🏢 Business Operations**: Allow employees to make purchases within approved limits
3. **🎮 Gaming**: Enable in-game characters to spend player tokens with limits
4. **🤖 DeFi Protocols**: Integrate with other contracts for automated spending
5. **👥 DAO Treasury**: Members can approve spending for specific purposes

## 🎯 Error Codes

- `u100` - ERR_UNAUTHORIZED: Access denied
- `u101` - ERR_INSUFFICIENT_BALANCE: Not enough STX in wallet
- `u102` - ERR_INSUFFICIENT_ALLOWANCE: Allowance too low for operation
- `u103` - ERR_WALLET_EXISTS: Wallet already created
- `u104` - ERR_WALLET_NOT_FOUND: Wallet doesn't exist
- `u105` - ERR_INVALID_AMOUNT: Amount must be greater than zero
- `u106` - ERR_SELF_APPROVAL: Cannot approve yourself
- `u107` - ERR_ALREADY_INITIALIZED: Contract already initialized

## 📊 Contract Data

The contract stores:
- **Wallets**: Balance, creation time, and active status
- **Allowances**: Approved spending amounts between users
- **Metadata**: Transaction counts and total amounts for analytics

## 🔮 Future Enhancements

- ⏰ Time-based allowances (expire after certain blocks)
- 🎯 Purpose-specific allowances (spending categories)
- 📱 Multi-signature wallet support
- 🔄 Recurring allowance refills
- 📈 Advanced analytics and reporting

---

Built with ❤️ using [Clarity](https://clarity-lang.org/) and [Stacks](https://stacks.org/)
