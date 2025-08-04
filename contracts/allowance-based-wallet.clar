(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INSUFFICIENT_ALLOWANCE (err u102))
(define-constant ERR_WALLET_EXISTS (err u103))
(define-constant ERR_WALLET_NOT_FOUND (err u104))
(define-constant ERR_INVALID_AMOUNT (err u105))
(define-constant ERR_SELF_APPROVAL (err u106))
(define-constant ERR_ALREADY_INITIALIZED (err u107))
(define-constant ERR_PAYMENT_NOT_FOUND (err u108))
(define-constant ERR_PAYMENT_NOT_DUE (err u109))
(define-constant ERR_PAYMENT_EXPIRED (err u110))
(define-constant ERR_INVALID_INTERVAL (err u111))
(define-constant ERR_BATCH_EMPTY (err u112))
(define-constant ERR_BATCH_TOO_LARGE (err u113))
(define-constant ERR_INVALID_OPERATION (err u114))

(define-data-var contract-owner principal tx-sender)

(define-map wallets
  { owner: principal }
  { 
    balance: uint,
    created-at: uint,
    is-active: bool
  }
)

(define-map allowances
  { 
    owner: principal, 
    spender: principal 
  }
  { amount: uint }
)

(define-map wallet-metadata
  { owner: principal }
  {
    total-deposited: uint,
    total-withdrawn: uint,
    total-approved: uint,
    transaction-count: uint
  }
)

(define-map scheduled-payments
  { 
    payment-id: uint,
    payer: principal
  }
  {
    recipient: principal,
    amount: uint,
    interval-blocks: uint,
    next-payment-block: uint,
    remaining-payments: uint,
    is-active: bool,
    created-at: uint
  }
)

(define-data-var payment-id-counter uint u0)
(define-data-var max-batch-size uint u10)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-read-only (get-wallet-balance (owner principal))
  (match (map-get? wallets { owner: owner })
    wallet (ok (get balance wallet))
    (err ERR_WALLET_NOT_FOUND)
  )
)

(define-read-only (get-wallet-info (owner principal))
  (match (map-get? wallets { owner: owner })
    wallet (ok wallet)
    (err ERR_WALLET_NOT_FOUND)
  )
)

(define-read-only (get-allowance (owner principal) (spender principal))
  (match (map-get? allowances { owner: owner, spender: spender })
    allowance (ok (get amount allowance))
    (ok u0)
  )
)

(define-read-only (get-wallet-metadata (owner principal))
  (match (map-get? wallet-metadata { owner: owner })
    metadata (ok metadata)
    (ok { 
      total-deposited: u0, 
      total-withdrawn: u0, 
      total-approved: u0, 
      transaction-count: u0 
    })
  )
)

(define-read-only (is-wallet-active (owner principal))
  (match (map-get? wallets { owner: owner })
    wallet (ok (get is-active wallet))
    (ok false)
  )
)

(define-read-only (get-scheduled-payment (payment-id uint) (payer principal))
  (match (map-get? scheduled-payments { payment-id: payment-id, payer: payer })
    payment (ok payment)
    (err ERR_PAYMENT_NOT_FOUND)
  )
)

(define-read-only (get-next-payment-id)
  (ok (+ (var-get payment-id-counter) u1))
)

(define-public (create-wallet)
  (let ((caller tx-sender))
    (asserts! (is-none (map-get? wallets { owner: caller })) ERR_WALLET_EXISTS)
    (map-set wallets 
      { owner: caller }
      { 
        balance: u0, 
        created-at: stacks-block-height,
        is-active: true
      }
    )
    (map-set wallet-metadata
      { owner: caller }
      {
        total-deposited: u0,
        total-withdrawn: u0,
        total-approved: u0,
        transaction-count: u0
      }
    )
    (ok caller)
  )
)

(define-public (deposit (amount uint))
  (let (
    (caller tx-sender)
    (current-wallet (unwrap! (map-get? wallets { owner: caller }) ERR_WALLET_NOT_FOUND))
    (current-metadata (unwrap! (map-get? wallet-metadata { owner: caller }) ERR_WALLET_NOT_FOUND))
  )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (get is-active current-wallet) ERR_UNAUTHORIZED)
    (try! (stx-transfer? amount caller (as-contract tx-sender)))
    (map-set wallets
      { owner: caller }
      (merge current-wallet { balance: (+ (get balance current-wallet) amount) })
    )
    (map-set wallet-metadata
      { owner: caller }
      (merge current-metadata { 
        total-deposited: (+ (get total-deposited current-metadata) amount),
        transaction-count: (+ (get transaction-count current-metadata) u1)
      })
    )
    (ok amount)
  )
)

(define-public (withdraw (amount uint))
  (let (
    (caller tx-sender)
    (current-wallet (unwrap! (map-get? wallets { owner: caller }) ERR_WALLET_NOT_FOUND))
    (current-balance (get balance current-wallet))
    (current-metadata (unwrap! (map-get? wallet-metadata { owner: caller }) ERR_WALLET_NOT_FOUND))
  )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (get is-active current-wallet) ERR_UNAUTHORIZED)
    (asserts! (>= current-balance amount) ERR_INSUFFICIENT_BALANCE)
    (try! (as-contract (stx-transfer? amount tx-sender caller)))
    (map-set wallets
      { owner: caller }
      (merge current-wallet { balance: (- current-balance amount) })
    )
    (map-set wallet-metadata
      { owner: caller }
      (merge current-metadata { 
        total-withdrawn: (+ (get total-withdrawn current-metadata) amount),
        transaction-count: (+ (get transaction-count current-metadata) u1)
      })
    )
    (ok amount)
  )
)

(define-public (approve (spender principal) (amount uint))
  (let (
    (caller tx-sender)
    (current-wallet (unwrap! (map-get? wallets { owner: caller }) ERR_WALLET_NOT_FOUND))
    (current-metadata (unwrap! (map-get? wallet-metadata { owner: caller }) ERR_WALLET_NOT_FOUND))
  )
    (asserts! (not (is-eq caller spender)) ERR_SELF_APPROVAL)
    (asserts! (get is-active current-wallet) ERR_UNAUTHORIZED)
    (map-set allowances
      { owner: caller, spender: spender }
      { amount: amount }
    )
    (map-set wallet-metadata
      { owner: caller }
      (merge current-metadata { 
        total-approved: (+ (get total-approved current-metadata) amount),
        transaction-count: (+ (get transaction-count current-metadata) u1)
      })
    )
    (ok amount)
  )
)

(define-public (transfer-from (owner principal) (recipient principal) (amount uint))
  (let (
    (spender tx-sender)
    (current-allowance (unwrap! (map-get? allowances { owner: owner, spender: spender }) ERR_INSUFFICIENT_ALLOWANCE))
    (allowance-amount (get amount current-allowance))
    (owner-wallet (unwrap! (map-get? wallets { owner: owner }) ERR_WALLET_NOT_FOUND))
    (owner-balance (get balance owner-wallet))
    (owner-metadata (unwrap! (map-get? wallet-metadata { owner: owner }) ERR_WALLET_NOT_FOUND))
  )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (get is-active owner-wallet) ERR_UNAUTHORIZED)
    (asserts! (>= allowance-amount amount) ERR_INSUFFICIENT_ALLOWANCE)
    (asserts! (>= owner-balance amount) ERR_INSUFFICIENT_BALANCE)
    
    (if (is-none (map-get? wallets { owner: recipient }))
      (map-set wallets 
        { owner: recipient }
        { 
          balance: amount, 
          created-at: stacks-block-height,
          is-active: true
        }
      )
      (let ((recipient-wallet (unwrap-panic (map-get? wallets { owner: recipient }))))
        (map-set wallets
          { owner: recipient }
          (merge recipient-wallet { balance: (+ (get balance recipient-wallet) amount) })
        )
      )
    )
    
    (map-set wallets
      { owner: owner }
      (merge owner-wallet { balance: (- owner-balance amount) })
    )
    
    (map-set allowances
      { owner: owner, spender: spender }
      { amount: (- allowance-amount amount) }
    )
    
    (map-set wallet-metadata
      { owner: owner }
      (merge owner-metadata { 
        transaction-count: (+ (get transaction-count owner-metadata) u1)
      })
    )
    (ok amount)
  )
)

(define-public (increase-allowance (spender principal) (added-value uint))
  (let (
    (caller tx-sender)
    (current-allowance (default-to u0 (get amount (map-get? allowances { owner: caller, spender: spender }))))
  )
    (approve spender (+ current-allowance added-value))
  )
)

(define-public (decrease-allowance (spender principal) (subtracted-value uint))
  (let (
    (caller tx-sender)
    (current-allowance (default-to u0 (get amount (map-get? allowances { owner: caller, spender: spender }))))
  )
    (if (>= current-allowance subtracted-value)
      (approve spender (- current-allowance subtracted-value))
      (approve spender u0)
    )
  )
)

(define-public (deactivate-wallet)
  (let (
    (caller tx-sender)
    (current-wallet (unwrap! (map-get? wallets { owner: caller }) ERR_WALLET_NOT_FOUND))
  )
    (asserts! (get is-active current-wallet) ERR_UNAUTHORIZED)
    (map-set wallets
      { owner: caller }
      (merge current-wallet { is-active: false })
    )
    (ok true)
  )
)

(define-public (reactivate-wallet)
  (let (
    (caller tx-sender)
    (current-wallet (unwrap! (map-get? wallets { owner: caller }) ERR_WALLET_NOT_FOUND))
  )
    (asserts! (not (get is-active current-wallet)) ERR_UNAUTHORIZED)
    (map-set wallets
      { owner: caller }
      (merge current-wallet { is-active: true })
    )
    (ok true)
  )
)

(define-public (emergency-withdraw-all)
  (let (
    (caller tx-sender)
    (current-wallet (unwrap! (map-get? wallets { owner: caller }) ERR_WALLET_NOT_FOUND))
    (current-balance (get balance current-wallet))
  )
    (asserts! (> current-balance u0) ERR_INSUFFICIENT_BALANCE)
    (withdraw current-balance)
  )
)

(define-public (create-scheduled-payment (recipient principal) (amount uint) (interval-blocks uint) (total-payments uint))
  (let (
    (caller tx-sender)
    (current-wallet (unwrap! (map-get? wallets { owner: caller }) ERR_WALLET_NOT_FOUND))
    (payment-id (+ (var-get payment-id-counter) u1))
    (current-metadata (unwrap! (map-get? wallet-metadata { owner: caller }) ERR_WALLET_NOT_FOUND))
  )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> interval-blocks u0) ERR_INVALID_INTERVAL)
    (asserts! (> total-payments u0) ERR_INVALID_AMOUNT)
    (asserts! (not (is-eq caller recipient)) ERR_SELF_APPROVAL)
    (asserts! (get is-active current-wallet) ERR_UNAUTHORIZED)
    (asserts! (>= (get balance current-wallet) (* amount total-payments)) ERR_INSUFFICIENT_BALANCE)
    
    (var-set payment-id-counter payment-id)
    (map-set scheduled-payments
      { payment-id: payment-id, payer: caller }
      {
        recipient: recipient,
        amount: amount,
        interval-blocks: interval-blocks,
        next-payment-block: (+ stacks-block-height interval-blocks),
        remaining-payments: total-payments,
        is-active: true,
        created-at: stacks-block-height
      }
    )
    (map-set wallet-metadata
      { owner: caller }
      (merge current-metadata { 
        transaction-count: (+ (get transaction-count current-metadata) u1)
      })
    )
    (ok payment-id)
  )
)

(define-public (execute-scheduled-payment (payment-id uint) (payer principal))
  (let (
    (payment (unwrap! (map-get? scheduled-payments { payment-id: payment-id, payer: payer }) ERR_PAYMENT_NOT_FOUND))
    (payer-wallet (unwrap! (map-get? wallets { owner: payer }) ERR_WALLET_NOT_FOUND))
    (recipient-address (get recipient payment))
    (payment-amount (get amount payment))
    (current-block stacks-block-height)
  )
    (asserts! (get is-active payment) ERR_PAYMENT_EXPIRED)
    (asserts! (>= current-block (get next-payment-block payment)) ERR_PAYMENT_NOT_DUE)
    (asserts! (> (get remaining-payments payment) u0) ERR_PAYMENT_EXPIRED)
    (asserts! (>= (get balance payer-wallet) payment-amount) ERR_INSUFFICIENT_BALANCE)
    
    (if (is-none (map-get? wallets { owner: recipient-address }))
      (map-set wallets 
        { owner: recipient-address }
        { 
          balance: payment-amount, 
          created-at: current-block,
          is-active: true
        }
      )
      (let ((recipient-wallet (unwrap-panic (map-get? wallets { owner: recipient-address }))))
        (map-set wallets
          { owner: recipient-address }
          (merge recipient-wallet { balance: (+ (get balance recipient-wallet) payment-amount) })
        )
      )
    )
    
    (map-set wallets
      { owner: payer }
      (merge payer-wallet { balance: (- (get balance payer-wallet) payment-amount) })
    )
    
    (let ((updated-remaining (- (get remaining-payments payment) u1)))
      (if (> updated-remaining u0)
        (map-set scheduled-payments
          { payment-id: payment-id, payer: payer }
          (merge payment {
            next-payment-block: (+ current-block (get interval-blocks payment)),
            remaining-payments: updated-remaining
          })
        )
        (map-set scheduled-payments
          { payment-id: payment-id, payer: payer }
          (merge payment {
            remaining-payments: u0,
            is-active: false
          })
        )
      )
    )
    (ok payment-amount)
  )
)

(define-public (cancel-scheduled-payment (payment-id uint))
  (let (
    (caller tx-sender)
    (payment (unwrap! (map-get? scheduled-payments { payment-id: payment-id, payer: caller }) ERR_PAYMENT_NOT_FOUND))
  )
    (asserts! (get is-active payment) ERR_PAYMENT_EXPIRED)
    (map-set scheduled-payments
      { payment-id: payment-id, payer: caller }
      (merge payment { is-active: false })
    )
    (ok true)
  )
)

(define-private (execute-batch-operation (operation { op-type: (string-ascii 20), recipient: (optional principal), amount: uint, spender: (optional principal) }))
  (let (
    (op-type (get op-type operation))
    (amount (get amount operation))
    (recipient (get recipient operation))
    (spender (get spender operation))
  )
    (if (is-eq op-type "deposit")
      (deposit amount)
      (if (is-eq op-type "withdraw")
        (withdraw amount)
        (if (is-eq op-type "approve")
          (match spender
            spender-addr (approve spender-addr amount)
            ERR_INVALID_OPERATION
          )
          (if (is-eq op-type "transfer")
            (match recipient
              recipient-addr (transfer-from tx-sender recipient-addr amount)
              ERR_INVALID_OPERATION
            )
            ERR_INVALID_OPERATION
          )
        )
      )
    )
  )
)

(define-public (batch-execute (operations (list 10 { op-type: (string-ascii 20), recipient: (optional principal), amount: uint, spender: (optional principal) })))
  (let (
    (batch-length (len operations))
  )
    (asserts! (> batch-length u0) ERR_BATCH_EMPTY)
    (asserts! (<= batch-length (var-get max-batch-size)) ERR_BATCH_TOO_LARGE)
    (asserts! (is-some (map-get? wallets { owner: tx-sender })) ERR_WALLET_NOT_FOUND)
    (match (fold check-and-execute operations (ok u0))
      success (ok true)
      error (err error)
    )
  )
)

(define-private (check-and-execute (operation { op-type: (string-ascii 20), recipient: (optional principal), amount: uint, spender: (optional principal) }) (previous-result (response uint uint)))
  (match previous-result
    success (match (execute-batch-operation operation)
      op-success (ok success)
      op-error (err op-error)
    )
    error (err error)
  )
)

(define-public (batch-deposit-and-approve (deposit-amount uint) (spender principal) (approve-amount uint))
  (begin
    (try! (deposit deposit-amount))
    (approve spender approve-amount)
  )
)

(define-public (batch-withdraw-and-transfer (withdraw-amount uint) (recipient principal) (transfer-amount uint))
  (begin
    (try! (withdraw withdraw-amount))
    (transfer-from tx-sender recipient transfer-amount)
  )
)

(define-public (batch-multiple-approvals (approvals (list 5 { spender: principal, amount: uint })))
  (let (
    (batch-length (len approvals))
  )
    (asserts! (> batch-length u0) ERR_BATCH_EMPTY)
    (asserts! (is-some (map-get? wallets { owner: tx-sender })) ERR_WALLET_NOT_FOUND)
    (match (fold process-approval approvals (ok u0))
      success (ok true)
      error (err error)
    )
  )
)

(define-private (process-approval (approval { spender: principal, amount: uint }) (previous-result (response uint uint)))
  (match previous-result
    success (match (approve (get spender approval) (get amount approval))
      approval-success (ok success)
      approval-error (err approval-error)
    )
    error (err error)
  )
)