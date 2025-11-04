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
(define-constant ERR_SPENDING_LIMIT_EXCEEDED (err u115))
(define-constant ERR_LIMIT_NOT_FOUND (err u116))
(define-constant ERR_INVALID_TIME_WINDOW (err u117))
(define-constant ERR_VAULT_NOT_FOUND (err u118))
(define-constant ERR_VAULT_LOCKED (err u119))
(define-constant ERR_VAULT_EXISTS (err u120))
(define-constant ERR_INSUFFICIENT_VAULT_BALANCE (err u121))

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

(define-map allowance-expiries
  {
    owner: principal,
    spender: principal
  }
  { expires-at: uint }
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

(define-map spending-limits
  {
    owner: principal,
    limit-type: (string-ascii 10)
  }
  {
    limit-amount: uint,
    window-blocks: uint,
    spent-amount: uint,
    window-start-block: uint,
    is-active: bool
  }
)

(define-map savings-vaults
  {
    owner: principal,
    vault-name: (string-ascii 50)
  }
  {
    balance: uint,
    target-amount: uint,
    unlock-block: uint,
    is-locked: bool,
    created-at: uint
  }
)

(define-data-var vault-counter uint u0)

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
  (let (
    (allowance-opt (map-get? allowances { owner: owner, spender: spender }))
    (expiry-opt (map-get? allowance-expiries { owner: owner, spender: spender }))
    (now stacks-block-height)
  )
    (match allowance-opt
      allowance
      (match expiry-opt
        expiry (if (> (get expires-at expiry) now) (ok (get amount allowance)) (ok u0))
        (ok (get amount allowance))
      )
      (ok u0)
    )
  )
)

(define-read-only (get-allowance-expiry (owner principal) (spender principal))
  (match (map-get? allowance-expiries { owner: owner, spender: spender })
    expiry (ok (some (get expires-at expiry)))
    (ok none)
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

(define-read-only (get-spending-limit (owner principal) (limit-type (string-ascii 10)))
  (match (map-get? spending-limits { owner: owner, limit-type: limit-type })
    limit (ok limit)
    (err ERR_LIMIT_NOT_FOUND)
  )
)

(define-read-only (get-remaining-spending-limit (owner principal) (limit-type (string-ascii 10)))
  (match (map-get? spending-limits { owner: owner, limit-type: limit-type })
    limit 
    (let (
      (current-block stacks-block-height)
      (window-start (get window-start-block limit))
      (window-blocks (get window-blocks limit))
      (spent-amount (get spent-amount limit))
      (limit-amount (get limit-amount limit))
    )
      (if (>= (- current-block window-start) window-blocks)
        (ok limit-amount)
        (ok (if (>= limit-amount spent-amount) 
          (- limit-amount spent-amount) 
          u0))
      )
    )
    (ok u0)
  )
)

(define-read-only (get-vault (owner principal) (vault-name (string-ascii 50)))
  (match (map-get? savings-vaults { owner: owner, vault-name: vault-name })
    vault (ok vault)
    (err ERR_VAULT_NOT_FOUND)
  )
)

(define-read-only (get-vault-progress (owner principal) (vault-name (string-ascii 50)))
  (match (map-get? savings-vaults { owner: owner, vault-name: vault-name })
    vault (ok {
      balance: (get balance vault),
      target: (get target-amount vault),
      percentage: (if (> (get target-amount vault) u0)
        (/ (* (get balance vault) u100) (get target-amount vault))
        u0
      ),
      goal-reached: (>= (get balance vault) (get target-amount vault))
    })
    (err ERR_VAULT_NOT_FOUND)
  )
)

(define-read-only (is-vault-unlocked (owner principal) (vault-name (string-ascii 50)))
  (match (map-get? savings-vaults { owner: owner, vault-name: vault-name })
    vault (ok (or 
      (not (get is-locked vault))
      (>= stacks-block-height (get unlock-block vault))
    ))
    (err ERR_VAULT_NOT_FOUND)
  )
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
    (try! (check-spending-limit caller amount))
    (try! (as-contract (stx-transfer? amount tx-sender caller)))
    (unwrap-panic (update-spending-tracking caller amount))
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
    (let ((expiry-opt (map-get? allowance-expiries { owner: owner, spender: spender })))
      (match expiry-opt
        expiry (asserts! (> (get expires-at expiry) stacks-block-height) ERR_INSUFFICIENT_ALLOWANCE)
        true
      )
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

(define-public (set-allowance-expiry (spender principal) (expiry-block uint))
  (let (
    (caller tx-sender)
  )
    (asserts! (> expiry-block stacks-block-height) ERR_INVALID_TIME_WINDOW)
    (map-set allowance-expiries
      { owner: caller, spender: spender }
      { expires-at: expiry-block }
    )
    (ok expiry-block)
  )
)

(define-public (clear-allowance-expiry (spender principal))
  (let ((caller tx-sender))
    (map-delete allowance-expiries { owner: caller, spender: spender })
    (ok true)
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

(define-private (check-spending-limit (owner principal) (amount uint))
  (let (
    (daily-limit (map-get? spending-limits { owner: owner, limit-type: "daily" }))
    (weekly-limit (map-get? spending-limits { owner: owner, limit-type: "weekly" }))
    (monthly-limit (map-get? spending-limits { owner: owner, limit-type: "monthly" }))
    (current-block stacks-block-height)
  )
    (match daily-limit
      limit (if (get is-active limit)
        (let (
          (window-start (get window-start-block limit))
          (window-blocks (get window-blocks limit))
          (spent-amount (get spent-amount limit))
          (limit-amount (get limit-amount limit))
          (current-spent (if (>= (- current-block window-start) window-blocks) u0 spent-amount))
        )
          (asserts! (<= (+ current-spent amount) limit-amount) ERR_SPENDING_LIMIT_EXCEEDED)
          (ok true)
        )
        (ok true)
      )
      (ok true)
    )
  )
)

(define-private (update-spending-tracking (owner principal) (amount uint))
  (let (
    (current-block stacks-block-height)
  )
    (match (map-get? spending-limits { owner: owner, limit-type: "daily" })
      daily-limit 
      (if (get is-active daily-limit)
        (let (
          (window-start (get window-start-block daily-limit))
          (window-blocks (get window-blocks daily-limit))
          (spent-amount (get spent-amount daily-limit))
          (is-new-window (>= (- current-block window-start) window-blocks))
        )
          (begin
            (map-set spending-limits
              { owner: owner, limit-type: "daily" }
              (merge daily-limit {
                spent-amount: (if is-new-window amount (+ spent-amount amount)),
                window-start-block: (if is-new-window current-block window-start)
              })
            )
            (ok true)
          )
        )
        (ok true)
      )
      (ok true)
    )
  )
)

(define-public (set-spending-limit (limit-type (string-ascii 10)) (limit-amount uint) (window-blocks uint))
  (let (
    (caller tx-sender)
    (current-wallet (unwrap! (map-get? wallets { owner: caller }) ERR_WALLET_NOT_FOUND))
  )
    (asserts! (> limit-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> window-blocks u0) ERR_INVALID_TIME_WINDOW)
    (asserts! (get is-active current-wallet) ERR_UNAUTHORIZED)
    (asserts! (or (is-eq limit-type "daily") (or (is-eq limit-type "weekly") (is-eq limit-type "monthly"))) ERR_INVALID_OPERATION)
    (map-set spending-limits
      { owner: caller, limit-type: limit-type }
      {
        limit-amount: limit-amount,
        window-blocks: window-blocks,
        spent-amount: u0,
        window-start-block: stacks-block-height,
        is-active: true
      }
    )
    (ok true)
  )
)

(define-public (update-spending-limit (limit-type (string-ascii 10)) (new-limit-amount uint))
  (let (
    (caller tx-sender)
    (current-limit (unwrap! (map-get? spending-limits { owner: caller, limit-type: limit-type }) ERR_LIMIT_NOT_FOUND))
  )
    (asserts! (> new-limit-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (get is-active current-limit) ERR_LIMIT_NOT_FOUND)
    (map-set spending-limits
      { owner: caller, limit-type: limit-type }
      (merge current-limit { limit-amount: new-limit-amount })
    )
    (ok true)
  )
)

(define-public (disable-spending-limit (limit-type (string-ascii 10)))
  (let (
    (caller tx-sender)
    (current-limit (unwrap! (map-get? spending-limits { owner: caller, limit-type: limit-type }) ERR_LIMIT_NOT_FOUND))
  )
    (map-set spending-limits
      { owner: caller, limit-type: limit-type }
      (merge current-limit { is-active: false })
    )
    (ok true)
  )
)

(define-public (enable-spending-limit (limit-type (string-ascii 10)))
  (let (
    (caller tx-sender)
    (current-limit (unwrap! (map-get? spending-limits { owner: caller, limit-type: limit-type }) ERR_LIMIT_NOT_FOUND))
  )
    (map-set spending-limits
      { owner: caller, limit-type: limit-type }
      (merge current-limit { is-active: true })
    )
    (ok true)
  )
)

(define-public (reset-spending-window (limit-type (string-ascii 10)))
  (let (
    (caller tx-sender)
    (current-limit (unwrap! (map-get? spending-limits { owner: caller, limit-type: limit-type }) ERR_LIMIT_NOT_FOUND))
  )
    (map-set spending-limits
      { owner: caller, limit-type: limit-type }
      (merge current-limit { 
        spent-amount: u0,
        window-start-block: stacks-block-height
      })
    )
    (ok true)
  )
)

(define-public (create-vault (vault-name (string-ascii 50)) (target-amount uint) (lock-blocks uint))
  (let (
    (caller tx-sender)
    (current-wallet (unwrap! (map-get? wallets { owner: caller }) ERR_WALLET_NOT_FOUND))
  )
    (asserts! (is-none (map-get? savings-vaults { owner: caller, vault-name: vault-name })) ERR_VAULT_EXISTS)
    (asserts! (> target-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (get is-active current-wallet) ERR_UNAUTHORIZED)
    (map-set savings-vaults
      { owner: caller, vault-name: vault-name }
      {
        balance: u0,
        target-amount: target-amount,
        unlock-block: (+ stacks-block-height lock-blocks),
        is-locked: (> lock-blocks u0),
        created-at: stacks-block-height
      }
    )
    (var-set vault-counter (+ (var-get vault-counter) u1))
    (ok vault-name)
  )
)

(define-public (deposit-to-vault (vault-name (string-ascii 50)) (amount uint))
  (let (
    (caller tx-sender)
    (current-wallet (unwrap! (map-get? wallets { owner: caller }) ERR_WALLET_NOT_FOUND))
    (vault (unwrap! (map-get? savings-vaults { owner: caller, vault-name: vault-name }) ERR_VAULT_NOT_FOUND))
    (current-balance (get balance current-wallet))
  )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= current-balance amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (get is-active current-wallet) ERR_UNAUTHORIZED)
    (map-set wallets
      { owner: caller }
      (merge current-wallet { balance: (- current-balance amount) })
    )
    (map-set savings-vaults
      { owner: caller, vault-name: vault-name }
      (merge vault { balance: (+ (get balance vault) amount) })
    )
    (ok amount)
  )
)

(define-public (withdraw-from-vault (vault-name (string-ascii 50)) (amount uint))
  (let (
    (caller tx-sender)
    (current-wallet (unwrap! (map-get? wallets { owner: caller }) ERR_WALLET_NOT_FOUND))
    (vault (unwrap! (map-get? savings-vaults { owner: caller, vault-name: vault-name }) ERR_VAULT_NOT_FOUND))
    (vault-balance (get balance vault))
    (is-unlocked (or (not (get is-locked vault)) (>= stacks-block-height (get unlock-block vault))))
  )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! is-unlocked ERR_VAULT_LOCKED)
    (asserts! (>= vault-balance amount) ERR_INSUFFICIENT_VAULT_BALANCE)
    (asserts! (get is-active current-wallet) ERR_UNAUTHORIZED)
    (map-set savings-vaults
      { owner: caller, vault-name: vault-name }
      (merge vault { balance: (- vault-balance amount) })
    )
    (map-set wallets
      { owner: caller }
      (merge current-wallet { balance: (+ (get balance current-wallet) amount) })
    )
    (ok amount)
  )
)

(define-public (close-vault (vault-name (string-ascii 50)))
  (let (
    (caller tx-sender)
    (current-wallet (unwrap! (map-get? wallets { owner: caller }) ERR_WALLET_NOT_FOUND))
    (vault (unwrap! (map-get? savings-vaults { owner: caller, vault-name: vault-name }) ERR_VAULT_NOT_FOUND))
    (vault-balance (get balance vault))
    (is-unlocked (or (not (get is-locked vault)) (>= stacks-block-height (get unlock-block vault))))
  )
    (asserts! is-unlocked ERR_VAULT_LOCKED)
    (asserts! (get is-active current-wallet) ERR_UNAUTHORIZED)
    (if (> vault-balance u0)
      (map-set wallets
        { owner: caller }
        (merge current-wallet { balance: (+ (get balance current-wallet) vault-balance) })
      )
      true
    )
    (map-delete savings-vaults { owner: caller, vault-name: vault-name })
    (ok vault-balance)
  )
)

(define-public (update-vault-target (vault-name (string-ascii 50)) (new-target uint))
  (let (
    (caller tx-sender)
    (vault (unwrap! (map-get? savings-vaults { owner: caller, vault-name: vault-name }) ERR_VAULT_NOT_FOUND))
  )
    (asserts! (> new-target u0) ERR_INVALID_AMOUNT)
    (map-set savings-vaults
      { owner: caller, vault-name: vault-name }
      (merge vault { target-amount: new-target })
    )
    (ok new-target)
  )
)

(define-public (extend-vault-lock (vault-name (string-ascii 50)) (additional-blocks uint))
  (let (
    (caller tx-sender)
    (vault (unwrap! (map-get? savings-vaults { owner: caller, vault-name: vault-name }) ERR_VAULT_NOT_FOUND))
    (current-unlock (get unlock-block vault))
  )
    (asserts! (> additional-blocks u0) ERR_INVALID_TIME_WINDOW)
    (asserts! (get is-locked vault) ERR_VAULT_NOT_FOUND)
    (map-set savings-vaults
      { owner: caller, vault-name: vault-name }
      (merge vault { unlock-block: (+ current-unlock additional-blocks) })
    )
    (ok (+ current-unlock additional-blocks))
  )
)
