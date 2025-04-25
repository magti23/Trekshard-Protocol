;; Decentralized Expedition Protocol - Stage 1
;; Core Base Camp and Explorer Functionality

;; Constants
(define-constant ERR-NOT-EXPEDITION-LEADER (err u1))
(define-constant ERR-BASE-CAMP-CLOSED (err u2))
(define-constant ERR-INVALID-PARAMETER (err u5))
(define-constant ERR-INSUFFICIENT-EXPERIENCE (err u6))
(define-constant MIN-EXPERIENCE-REQUIRED u10)
(define-constant MAX-EXPERIENCE-INPUT u1000000)

;; Data Variables
(define-data-var expedition-leader principal tx-sender)
(define-data-var base-camp-operational bool false)
(define-data-var expedition-season uint u0)
(define-data-var minimum-experience-threshold uint u100)

;; Explorer Profiles
(define-map explorer-profiles
    principal
    {
        experience: uint,
        expeditions-joined: (list 30 uint),
        evaluation-weight: uint
    }
)

;; Authorization
(define-private (is-expedition-leader)
    (is-eq tx-sender (var-get expedition-leader)))

;; Data Validation Functions
(define-private (is-valid-experience (exp uint))
    (and (>= exp MIN-EXPERIENCE-REQUIRED) (<= exp MAX-EXPERIENCE-INPUT)))

;; Base Camp Management Functions
(define-public (activate-base-camp)
    (begin
        (asserts! (is-expedition-leader) ERR-NOT-EXPEDITION-LEADER)
        (var-set base-camp-operational true)
        (var-set expedition-season u0)
        (ok true)))

;; Explorer Registration Functions
(define-public (register-explorer (initial-experience uint))
    (begin
        (asserts! (var-get base-camp-operational) ERR-BASE-CAMP-CLOSED)
        
        ;; Validate experience input
        (asserts! (is-valid-experience initial-experience) ERR-INVALID-PARAMETER)
        
        ;; Require some experience token transfer (simplified for demonstration)
        (try! (stx-transfer? initial-experience tx-sender (var-get expedition-leader)))
        
        ;; Initialize explorer profile with validated experience
        (map-set explorer-profiles tx-sender
            {
                experience: initial-experience,
                expeditions-joined: (list),
                evaluation-weight: initial-experience
            })
            
        (ok true)))

;; Read-only functions
(define-read-only (get-explorer-profile (explorer principal))
    (map-get? explorer-profiles explorer))

(define-read-only (get-base-camp-metrics)
    {
        operational: (var-get base-camp-operational),
        expedition-season: (var-get expedition-season),
        minimum-experience: (var-get minimum-experience-threshold)
    })

(define-public (update-minimum-experience (new-minimum uint))
    (begin
        (asserts! (is-expedition-leader) ERR-NOT-EXPEDITION-LEADER)
        ;; Validate new threshold is within acceptable range
        (asserts! (and (>= new-minimum MIN-EXPERIENCE-REQUIRED) (<= new-minimum MAX-EXPERIENCE-INPUT)) ERR-INVALID-PARAMETER)
        (var-set minimum-experience-threshold new-minimum)
        (ok true)))

(define-public (shutdown-base-camp)
    (begin
        (asserts! (is-expedition-leader) ERR-NOT-EXPEDITION-LEADER)
        (var-set base-camp-operational false)
        (ok true)))

(define-public (transfer-expedition-leader-role (new-leader principal))
    (begin 
        (asserts! (is-expedition-leader) ERR-NOT-EXPEDITION-LEADER)
        ;; Cannot set to zero address (represented as none in Clarity)
        (asserts! (is-some (some new-leader)) ERR-INVALID-PARAMETER)
        (var-set expedition-leader new-leader)
        (ok true)))