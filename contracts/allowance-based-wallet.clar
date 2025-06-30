(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INSUFFICIENT_ALLOWANCE (err u102))
(define-constant ERR_WALLET_EXISTS (err u103))
(define-constant ERR_WALLET_NOT_FOUND (err u104))
(define-constant ERR_INVALID_AMOUNT (err u105))
(define-constant ERR_SELF_APPROVAL (err u106))
(define-constant ERR_ALREADY_INITIALIZED (err u107))

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
