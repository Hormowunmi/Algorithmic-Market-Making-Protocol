;; Algorithmic Market Making Protocol
;; A dynamic market maker that adjusts parameters based on market conditions

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-pool-exists (err u102))
(define-constant err-pool-not-found (err u103))
(define-constant err-token-exists (err u104))
(define-constant err-token-not-found (err u105))
(define-constant err-insufficient-balance (err u106))
(define-constant err-zero-amount (err u107))
(define-constant err-price-impact-too-high (err u108))
(define-constant err-slippage-too-high (err u109))
(define-constant err-insufficient-liquidity (err u110))
(define-constant err-invalid-parameters (err u111))
(define-constant err-range-invalid (err u112))
(define-constant err-position-not-found (err u113))
(define-constant err-emergency-shutdown (err u114))
(define-constant err-min-deposit (err u115))
(define-constant err-position-still-active (err u116))
(define-constant err-paused (err u117))
(define-constant err-oracle-error (err u118))
(define-constant err-oracle-stale (err u119))
(define-constant err-unauthorized-oracle (err u120))
(define-constant err-invalid-curve (err u121))
(define-constant err-range-outside-pool (err u122))
(define-constant err-rewards-claimed-already (err u123))
(define-constant err-no-rewards-available (err u124))

;; Protocol parameters
(define-data-var next-pool-id uint u1)
(define-data-var next-position-id uint u1)
(define-data-var protocol-fee-bp uint u30) ;; 0.3% base protocol fee in basis points
(define-data-var min-deposit-amount uint u1000000) ;; 1 STX minimum deposit
(define-data-var emergency-shutdown bool false)
(define-data-var treasury-address principal contract-owner)
(define-data-var volatility-update-frequency uint u144) ;; Update volatility approx once per day
(define-data-var max-price-impact-bp uint u300) ;; 3% max price impact
(define-data-var impermanent-loss-threshold uint u500) ;; 5% threshold for IL protection
(define-data-var impermanent-loss-coverage-bp uint u5000) ;; 50% IL coverage
(define-data-var dynamic-range-adjustment-factor uint u500) ;; 5% range adjustment
(define-data-var price-deviation-threshold uint u200) ;; 2% threshold for price deviation
(define-data-var max-dynamic-fee-increase uint u500) ;; Maximum 5% fee increase

;; Curve types enumeration
;; 0 = Constant Product (x*y=k), 1 = Stableswap, 2 = Exponential, 3 = Dynamic
(define-data-var curve-types (list 4 (string-ascii 20)) (list "ConstantProduct" "Stableswap" "Exponential" "Dynamic"))

;; Pool status enumeration
;; 0 = Active, 1 = Paused, 2 = Deprecated
(define-data-var pool-statuses (list 3 (string-ascii 10)) (list "Active" "Paused" "Deprecated"))

;; Range status enumeration
;; 0 = Out-of-range, 1 = In-range, 2 = Partial-range
(define-data-var range-statuses (list 3 (string-ascii 15)) (list "Out-of-range" "In-range" "Partial-range"))

;; Supported tokens
(define-map token-registry
  { token-id: (string-ascii 20) }
  {
    name: (string-ascii 40),
    token-type: (string-ascii 10), ;; "fungible" or "non-fungible"
    contract: principal,
    decimals: uint,
    price-oracle: principal,
    volatility-history: (list 30 uint), ;; Recent volatility measurements
    current-volatility: uint, ;; Current volatility score 1-10000
    is-stable: bool, ;; Is this a stablecoin
    max-supply: uint,
    last-price: uint, ;; Last price in STX with 8 decimals
    last-update-block: uint
  }
)
;; Liquidity pools
(define-map liquidity-pools
  { pool-id: uint }
  {
    token-x: (string-ascii 20),
    token-y: (string-ascii 20),
    reserve-x: uint,
    reserve-y: uint,
    virtual-reserve-x: uint, ;; Used for stableswap and custom curves
    virtual-reserve-y: uint,
    liquidity-units: uint, ;; Total liquidity shares
    curve-type: uint,
    curve-params: (list 5 uint), ;; Custom parameters for the curve
    base-fee-bp: uint, ;; Base fee in basis points
    dynamic-fee-bp: uint, ;; Additional dynamic fee based on volatility
    current-tick: int, ;; Current price tick (log base 1.0001 of price)
    tick-spacing: uint, ;; Minimum tick movement
    price-oracle: principal,
    total-volume-x: uint,
    total-volume-y: uint,
    total-fees-x: uint,
    total-fees-y: uint,
    total-fees-protocol: uint,
    creation-block: uint,
    last-update-block: uint,
    status: uint, ;; 0=Active, 1=Paused, 2=Deprecated
    price-history: (list 24 { price: uint, timestamp: uint }), ;; 24 hours of price history
    volatility-adjustment: uint, ;; Dynamic adjustment to fee and ranges
    concentrated-ranges: (list 10 { 
      tick-lower: int, 
      tick-upper: int, 
      liquidity: uint, 
      positions-count: uint 
    }),
    total-il-compensation-paid: uint
  }
)

;; Liquidity positions
(define-map liquidity-positions
  { position-id: uint }
  {
    pool-id: uint,
    provider: principal,
    liquidity-units: uint, ;; Share of the pool
    token-x-amount: uint,
    token-y-amount: uint,
    entry-price: uint, ;; Entry price for impermanent loss calculation
    entry-sqrt-price: uint, ;; Square root of price at entry (for concentrated liquidity)
    entry-block: uint,
    last-update-block: uint,
    tick-lower: int, ;; Lower tick bound for concentrated liquidity
    tick-upper: int, ;; Upper tick bound for concentrated liquidity
    range-status: uint, ;; 0=Out-of-range, 1=In-range, 2=Partial-range
    fees-earned-x: uint,
    fees-earned-y: uint,
    rewards-earned: uint,
    rewards-claimed: uint,
    il-compensation: uint,
    is-concentrated: bool ;; Is this a concentrated liquidity position
  }
)

;; User positions index
(define-map user-positions
  { user: principal }
  { position-ids: (list 100 uint) }
)

;; Pool positions index
(define-map pool-positions
  { pool-id: uint }
  { position-ids: (list 500 uint) }
)

;; Oracle price data
(define-map oracle-prices
  { token-id: (string-ascii 20) }
  {
    price: uint, ;; Price in STX with 8 decimals
    last-update-block: uint,
    twap-price: uint, ;; Time-weighted average price
    trusted: bool,
    oracle-address: principal
  }
)

;; Initialize the protocol
(define-public (initialize (treasury principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set treasury-address treasury)
    (var-set protocol-fee-bp u30) ;; 0.3%
    (var-set min-deposit-amount u1000000) ;; 1 STX
    (var-set emergency-shutdown false)
    
    (ok true)
  )
)

;; Register a token
(define-public (register-token
  (token-id (string-ascii 20))
  (name (string-ascii 40))
  (token-type (string-ascii 10))
  (contract principal)
  (decimals uint)
  (price-oracle principal)
  (is-stable bool)
  (max-supply uint))
  
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (var-get emergency-shutdown)) err-emergency-shutdown)
    (asserts! (is-none (map-get? token-registry { token-id: token-id })) err-token-exists)
    
    ;; Create token registry entry
    (map-set token-registry
      { token-id: token-id }
      {
        name: name,
        token-type: token-type,
        contract: contract,
        decimals: decimals,
        price-oracle: price-oracle,
        volatility-history: (list u0 u0 u0 u0 u0 u0 u0 u0 u0 u0),
        current-volatility: u1000, ;; Start with medium volatility (10%)
        is-stable: is-stable,
        max-supply: max-supply,
        last-price: u0,
        last-update-block: block-height
      }
    )
    
    ;; Initialize oracle entry
    (map-set oracle-prices
      { token-id: token-id }
      {
        price: u0,
        last-update-block: block-height,
        twap-price: u0,
        trusted: true,
        oracle-address: price-oracle
      }
    )
    
    (ok token-id)
  )
)
;; Create a new liquidity pool
(define-public (create-pool
  (token-x (string-ascii 20))
  (token-y (string-ascii 20))
  (curve-type uint)
  (curve-params (list 5 uint))
  (base-fee-bp uint)
  (tick-spacing uint))
  
  (let (
    (pool-id (var-get next-pool-id))
    (token-x-info (unwrap! (map-get? token-registry { token-id: token-x }) err-token-not-found))
    (token-y-info (unwrap! (map-get? token-registry { token-id: token-y }) err-token-not-found))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (var-get emergency-shutdown)) err-emergency-shutdown)
    (asserts! (< curve-type u4) err-invalid-curve) ;; Valid curve type
    (asserts! (<= base-fee-bp u500) err-invalid-parameters) ;; Max 5% base fee
    (asserts! (> tick-spacing u0) err-invalid-parameters) ;; Tick spacing must be positive
    
    ;; Create pool
    (map-set liquidity-pools
      { pool-id: pool-id }
      {
        token-x: token-x,
        token-y: token-y,
        reserve-x: u0,
        reserve-y: u0,
        virtual-reserve-x: u0,
        virtual-reserve-y: u0,
        liquidity-units: u0,
        curve-type: curve-type,
        curve-params: curve-params,
        base-fee-bp: base-fee-bp,
        dynamic-fee-bp: u0, ;; Start with no dynamic fee
        current-tick: (convert-to-int 0), ;; Start at price = 1.0
        tick-spacing: tick-spacing,
        price-oracle: (get price-oracle token-x-info), ;; Use token X's oracle by default
        total-volume-x: u0,
        total-volume-y: u0,
        total-fees-x: u0,
        total-fees-y: u0,
        total-fees-protocol: u0,
        creation-block: block-height,
        last-update-block: block-height,
        status: u0, ;; Active
        price-history: (list),
        volatility-adjustment: u1000, ;; Start with 10% volatility adjustment
        concentrated-ranges: (list),
        total-il-compensation-paid: u0
      }
    )
    
    ;; Initialize pool positions list
    (map-set pool-positions
      { pool-id: pool-id }
      { position-ids: (list) }
    )
    
    ;; Increment pool ID counter
    (var-set next-pool-id (+ pool-id u1))
    
    (ok { pool-id: pool-id })
  )
)

;; Add standard liquidity to a pool
(define-public (add-liquidity
  (pool-id uint)
  (amount-x uint)
  (amount-y uint)
  (min-lp-units uint))
  
  (let (
    (provider tx-sender)
    (pool (unwrap! (map-get? liquidity-pools { pool-id: pool-id }) err-pool-not-found))
    (token-x (get token-x pool))
    (token-y (get token-y pool))
    (token-x-info (unwrap! (map-get? token-registry { token-id: token-x }) err-token-not-found))
    (token-y-info (unwrap! (map-get? token-registry { token-id: token-y }) err-token-not-found))
    (position-id (var-get next-position-id))
  )
    ;; Validation
    (asserts! (not (var-get emergency-shutdown)) err-emergency-shutdown)
    (asserts! (is-eq (get status pool) u0) err-paused) ;; Pool must be active
    (asserts! (> amount-x u0) err-zero-amount)
    (asserts! (> amount-y u0) err-zero-amount)
    (asserts! (>= amount-x (var-get min-deposit-amount)) err-min-deposit) ;; Minimum deposit
    (asserts! (>= amount-y (var-get min-deposit-amount)) err-min-deposit) ;; Minimum deposit
    
    ;; Calculate liquidity units (LP tokens)
    (let (
      (current-liquidity (get liquidity-units pool))
      (reserve-x (get reserve-x pool))
      (reserve-y (get reserve-y pool))
      (lp-units (if (is-eq current-liquidity u0)
                   ;; First liquidity provision - use geometric mean
                   (sqrti (* amount-x amount-y))
                   ;; Proportional to existing reserves
                   (min
                     (/ (* amount-x current-liquidity) reserve-x)
                     (/ (* amount-y current-liquidity) reserve-y)
                   )))
    )
      ;; Ensure minimum liquidity
      (asserts! (>= lp-units min-lp-units) err-slippage-too-high)
      
      ;; Transfer tokens to pool
      (try! (transfer-token token-x amount-x provider (as-contract tx-sender)))
      (try! (transfer-token token-y amount-y provider (as-contract tx-sender)))
      
      ;; Update pool state
      (map-set liquidity-pools
        { pool-id: pool-id }
        (merge pool {
          reserve-x: (+ reserve-x amount-x),
          reserve-y: (+ reserve-y amount-y),
          liquidity-units: (+ current-liquidity lp-units),
          last-update-block: block-height
        })
      )
      
      ;; Create liquidity position
      (map-set liquidity-positions
        { position-id: position-id }
        {
          pool-id: pool-id,
          provider: provider,
          liquidity-units: lp-units,
          token-x-amount: amount-x,
          token-y-amount: amount-y,
          entry-price: (calculate-price pool),
          entry-sqrt-price: (sqrti (/ reserve-y reserve-x)),
          entry-block: block-height,
          last-update-block: block-height,
          tick-lower: (convert-to-int 0), ;; Full range
          tick-upper: (convert-to-int 0), ;; Full range
          range-status: u1, ;; In-range
          fees-earned-x: u0,
          fees-earned-y: u0,
          rewards-earned: u0,
          rewards-claimed: u0,
          il-compensation: u0,
          is-concentrated: false
        }
      )
      
      ;; Update user's positions list
      (let (
        (user-pos (default-to { position-ids: (list) } (map-get? user-positions { user: provider })))
        (updated-user-pos (merge user-pos {
          position-ids: (append (get position-ids user-pos) position-id)
        }))
      )
        (map-set user-positions
          { user: provider }
          updated-user-pos
        )
      )
      
      ;; Update pool's positions list
      (let (
        (pool-pos (default-to { position-ids: (list) } (map-get? pool-positions { pool-id: pool-id })))
        (updated-pool-pos (merge pool-pos {
          position-ids: (append (get position-ids pool-pos) position-id)
        }))
      )
        (map-set pool-positions
          { pool-id: pool-id }
          updated-pool-pos
        )
      )
      
      ;; Increment position ID counter
      (var-set next-position-id (+ position-id u1))
      
      (ok { 
        position-id: position-id, 
        lp-units: lp-units,
        amount-x: amount-x,
        amount-y: amount-y 
      })
    )
  )
)

;; Add concentrated liquidity within a specific price range
(define-public (add-concentrated-liquidity
  (pool-id uint)
  (amount-x uint)
  (amount-y uint)
  (tick-lower int)
  (tick-upper int)
  (min-lp-units uint))
  
  (let (
    (provider tx-sender)
    (pool (unwrap! (map-get? liquidity-pools { pool-id: pool-id }) err-pool-not-found))
    (token-x (get token-x pool))
    (token-y (get token-y pool))
    (token-x-info (unwrap! (map-get? token-registry { token-id: token-x }) err-token-not-found))
    (token-y-info (unwrap! (map-get? token-registry { token-id: token-y }) err-token-not-found))
    (position-id (var-get next-position-id))
    (current-tick (get current-tick pool))
    (tick-spacing (get tick-spacing pool))
  )
    ;; Validation
    (asserts! (not (var-get emergency-shutdown)) err-emergency-shutdown)
    (asserts! (is-eq (get status pool) u0) err-paused) ;; Pool must be active
    (asserts! (> amount-x u0) err-zero-amount)
    (asserts! (> amount-y u0) err-zero-amount)
    (asserts! (>= amount-x (var-get min-deposit-amount)) err-min-deposit) ;; Minimum deposit
    (asserts! (>= amount-y (var-get min-deposit-amount)) err-min-deposit) ;; Minimum deposit
    (asserts! (< tick-lower tick-upper) err-range-invalid) ;; Valid range
    
    ;; Ensure ticks are on the spacing grid
    (asserts! (is-eq (mod tick-lower (convert-to-int tick-spacing)) (convert-to-int 0)) err-invalid-parameters)
    (asserts! (is-eq (mod tick-upper (convert-to-int tick-spacing)) (convert-to-int 0)) err-invalid-parameters)
    
    ;; Calculate liquidity provision based on range
    (let (
      (price-sqrt (sqrti (/ (get reserve-y pool) (get reserve-x pool))))
      (lower-price-sqrt (calculate-sqrt-price-from-tick tick-lower))
      (upper-price-sqrt (calculate-sqrt-price-from-tick tick-upper))
      (is-current-in-range (and (>= current-tick tick-lower) (< current-tick tick-upper)))
      (range-status (if is-current-in-range u1 u0)) ;; 1=In-range, 0=Out-of-range
      (lp-units (calculate-concentrated-liquidity amount-x amount-y price-sqrt lower-price-sqrt upper-price-sqrt))
    )
      ;; Ensure minimum liquidity
      (asserts! (>= lp-units min-lp-units) err-slippage-too-high)
      
      ;; Transfer tokens to pool
      (try! (transfer-token token-x amount-x provider (as-contract tx-sender)))
      (try! (transfer-token token-y amount-y provider (as-contract tx-sender)))
      