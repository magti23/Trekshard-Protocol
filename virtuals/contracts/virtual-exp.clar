;; Decentralized Expedition Protocol - Stage 2
;; Added Expedition Registration and Management

;; Constants
(define-constant ERR-NOT-EXPEDITION-LEADER (err u1))
(define-constant ERR-BASE-CAMP-CLOSED (err u2))
(define-constant ERR-INVALID-EXPEDITION (err u3))
(define-constant ERR-EXPEDITION-LOCKED (err u4))
(define-constant ERR-INVALID-PARAMETER (err u5))
(define-constant ERR-INSUFFICIENT-EXPERIENCE (err u6))
(define-constant ERR-EXPEDITION-EXISTS (err u7))
(define-constant ERR-NOT-AUTHORIZED (err u9))
(define-constant MAX-EXPEDITION-ID u1000)
(define-constant MIN-EXPERIENCE-REQUIRED u10)
(define-constant MAX-EXPERIENCE-INPUT u1000000)

;; Data Variables
(define-data-var expedition-leader principal tx-sender)
(define-data-var base-camp-operational bool false)
(define-data-var expedition-season uint u0)
(define-data-var minimum-experience-threshold uint u100)

;; Expedition Structure
(define-map expeditions
    uint
    {
        expedition-name: (string-utf8 128),
        description: (string-utf8 512),
        location-hash: (buff 32),
        terrain-type: (string-utf8 64),
        open-for-discoveries: bool,
        organizer: principal,
        total-experience: uint,
        validated-discoveries: uint
    }
)

;; Expedition Explorers Mapping
(define-map expedition-explorers
    {expedition-id: uint, explorer: principal}
    {
        experience-committed: uint
    }
)

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
(define-private (is-valid-hash (hash (buff 32)))
    (> (len hash) u0))

(define-private (is-valid-experience (exp uint))
    (and (>= exp MIN-EXPERIENCE-REQUIRED) (<= exp MAX-EXPERIENCE-INPUT)))

;; Base Camp Management Functions
(define-public (activate-base-camp)
    (begin
        (asserts! (is-expedition-leader) ERR-NOT-EXPEDITION-LEADER)
        (var-set base-camp-operational true)
        (var-set expedition-season u0)
        (ok true)))

(define-public (register-expedition
    (expedition-id uint)
    (expedition-name (string-utf8 128))
    (description (string-utf8 512))
    (location-hash (buff 32))
    (terrain-type (string-utf8 64)))
    (let (
        (explorer-profile (unwrap! (map-get? explorer-profiles tx-sender) ERR-INSUFFICIENT-EXPERIENCE))
        (validated-hash (if (is-valid-hash location-hash) location-hash 0x))
        )
        
        ;; Check base camp status
        (asserts! (var-get base-camp-operational) ERR-BASE-CAMP-CLOSED)
        
        ;; Validate expedition-id is within acceptable range
        (asserts! (<= expedition-id MAX-EXPEDITION-ID) ERR-INVALID-PARAMETER)
        
        ;; Check if expedition already exists
        (asserts! (is-none (map-get? expeditions expedition-id)) ERR-EXPEDITION-EXISTS)
        
        ;; Validate expedition-name and description are not empty
        (asserts! (> (len expedition-name) u0) ERR-INVALID-PARAMETER)
        (asserts! (> (len description) u0) ERR-INVALID-PARAMETER)
        (asserts! (> (len terrain-type) u0) ERR-INVALID-PARAMETER)
        
        ;; Validate hash is not empty
        (asserts! (is-valid-hash location-hash) ERR-INVALID-PARAMETER)
        
        ;; Check explorer has enough experience to register expedition
        (asserts! (>= (get experience explorer-profile) (var-get minimum-experience-threshold)) ERR-INSUFFICIENT-EXPERIENCE)
        
        ;; Set the expedition data
        (map-set expeditions expedition-id
            {
                expedition-name: expedition-name,
                description: description,
                location-hash: validated-hash,
                terrain-type: terrain-type,
                open-for-discoveries: true,
                organizer: tx-sender,
                total-experience: (get experience explorer-profile),
                validated-discoveries: u0
            })
        
        ;; Record explorer as expedition member
        (map-set expedition-explorers 
            {expedition-id: expedition-id, explorer: tx-sender}
            {experience-committed: (get experience explorer-profile)})
        
        ;; Update explorer profile
        (map-set explorer-profiles tx-sender
            (merge explorer-profile {
                expeditions-joined: (unwrap! (as-max-len? 
                    (append (get expeditions-joined explorer-profile) expedition-id) u30)
                    ERR-INVALID-PARAMETER)
            }))
        
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

;; Change Expedition Discovery Status
(define-public (set-expedition-discovery-status (expedition-id uint) (open bool))
    (let (
        (expedition (unwrap! (map-get? expeditions expedition-id) ERR-INVALID-EXPEDITION))
        )
        
        ;; Check base camp status
        (asserts! (var-get base-camp-operational) ERR-BASE-CAMP-CLOSED)
        
        ;; Only organizer or expedition leader can change status
        (asserts! (or (is-eq tx-sender (get organizer expedition)) (is-expedition-leader)) ERR-NOT-AUTHORIZED)
        
        ;; Update expedition status
        (map-set expeditions expedition-id
            (merge expedition {open-for-discoveries: open}))
        
        (ok true)))

;; Finalize Season
(define-public (finalize-season)
    (begin
        ;; Only expedition leader can finalize season
        (asserts! (is-expedition-leader) ERR-NOT-AUTHORIZED)
        (asserts! (var-get base-camp-operational) ERR-BASE-CAMP-CLOSED)
        
        ;; Advance expedition season
        (var-set expedition-season (+ (var-get expedition-season) u1))
        
        (ok true)))

;; Read-only functions
(define-read-only (get-expedition-details (expedition-id uint))
    (map-get? expeditions expedition-id))

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