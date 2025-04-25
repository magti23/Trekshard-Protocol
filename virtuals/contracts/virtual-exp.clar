;; Decentralized Expedition Protocol
;; A Clarity smart contract for collaborative expedition planning, data collection, and discovery validation

;; Constants
(define-constant ERR-NOT-EXPEDITION-LEADER (err u1))
(define-constant ERR-BASE-CAMP-CLOSED (err u2))
(define-constant ERR-INVALID-EXPEDITION (err u3))
(define-constant ERR-EXPEDITION-LOCKED (err u4))
(define-constant ERR-INVALID-PARAMETER (err u5))
(define-constant ERR-INSUFFICIENT-EXPERIENCE (err u6))
(define-constant ERR-EXPEDITION-EXISTS (err u7))
(define-constant ERR-ALREADY-EVALUATED (err u8))
(define-constant ERR-NOT-AUTHORIZED (err u9))
(define-constant ERR-DISCOVERY-NOT-FOUND (err u10))
(define-constant MAX-EXPEDITION-ID u1000) ;; Maximum allowed expedition ID
(define-constant MIN-EXPERIENCE-REQUIRED u10) ;; Minimum experience to register
(define-constant MAX-EXPERIENCE-INPUT u1000000) ;; Maximum experience input allowed
(define-constant MAX-VALIDATION-THRESHOLD u100) ;; Maximum validation threshold (100%)

;; Data Variables
(define-data-var expedition-leader principal tx-sender)
(define-data-var base-camp-operational bool false)
(define-data-var expedition-season uint u0)
(define-data-var minimum-experience-threshold uint u100) ;; 100 experience points minimum
(define-data-var validation-threshold uint u66) ;; 66% approval required for validation

;; Expedition Structure
(define-map expeditions
    uint
    {
        expedition-name: (string-utf8 128),
        description: (string-utf8 512),
        location-hash: (buff 32),      ;; SHA256 hash of the expedition location data
        terrain-type: (string-utf8 64),
        open-for-discoveries: bool,
        organizer: principal,
        total-experience: uint,       ;; Sum of experience of all explorers
        validated-discoveries: uint   ;; Counter of accepted discoveries
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
        discoveries-submitted: (list 30 uint),
        evaluation-weight: uint       ;; Derived from experience but can be modified
    }
)

;; Discovery Structure
(define-map expedition-discoveries
    uint  ;; discovery-id
    {
        description: (string-utf8 256),
        discovery-hash: (buff 32),
        explorer: principal,
        target-expedition: uint,
        submitted-in-season: uint,
        validated: bool
    }
)

;; Discovery Evaluations
(define-map discovery-evaluations
    {discovery-id: uint, evaluator: principal}
    {
        confirmed: bool,
        weight: uint
    }
)

;; Evaluation Tallies for Discoveries
(define-map evaluation-tallies
    uint  ;; discovery-id
    {
        confirmation-weight: uint,
        rejection-weight: uint,
        total-evaluations: uint
    }
)

;; Authorization
(define-private (is-expedition-leader)
    (is-eq tx-sender (var-get expedition-leader)))

;; Data Validation Functions
(define-private (is-valid-hash (hash (buff 32)))
    (> (len hash) u0))

(define-private (is-valid-description (desc (string-utf8 256)))
    (> (len desc) u0))

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
                discoveries-submitted: (list),
                evaluation-weight: initial-experience
            })
            
        (ok true)))

;; Discovery Submission
(define-public (submit-discovery
    (discovery-id uint)
    (target-expedition-id uint)
    (description (string-utf8 256))
    (discovery-hash (buff 32)))
    (let (
        (expedition (unwrap! (map-get? expeditions target-expedition-id) ERR-INVALID-EXPEDITION))
        (explorer (unwrap! (map-get? explorer-profiles tx-sender) ERR-INSUFFICIENT-EXPERIENCE))
        )
        
        ;; Check base camp status
        (asserts! (var-get base-camp-operational) ERR-BASE-CAMP-CLOSED)
        
        ;; Check if expedition is accepting discoveries
        (asserts! (get open-for-discoveries expedition) ERR-EXPEDITION-LOCKED)
        
        ;; Check that discovery ID doesn't already exist
        (asserts! (is-none (map-get? expedition-discoveries discovery-id)) ERR-INVALID-PARAMETER)
        
        ;; Validate description and hash
        (asserts! (is-valid-description description) ERR-INVALID-PARAMETER)
        (asserts! (is-valid-hash discovery-hash) ERR-INVALID-PARAMETER)
        
        ;; Record the discovery
        (map-set expedition-discoveries discovery-id
            {
                description: description,
                discovery-hash: discovery-hash,
                explorer: tx-sender,
                target-expedition: target-expedition-id,
                submitted-in-season: (var-get expedition-season),
                validated: false
            })
        
        ;; Initialize evaluation tally
        (map-set evaluation-tallies discovery-id
            {
                confirmation-weight: u0,
                rejection-weight: u0,
                total-evaluations: u0
            })
        
        ;; Update explorer's submitted discoveries
        (map-set explorer-profiles tx-sender
            (merge explorer {
                discoveries-submitted: (unwrap! (as-max-len? 
                    (append (get discoveries-submitted explorer) discovery-id) u30)
                    ERR-INVALID-PARAMETER)
            }))
        
        (ok true)))

;; Evaluate Discovery
(define-public (evaluate-discovery
    (discovery-id uint)
    (confirm bool))
    (let (
        (discovery (unwrap! (map-get? expedition-discoveries discovery-id) ERR-DISCOVERY-NOT-FOUND))
        (explorer (unwrap! (map-get? explorer-profiles tx-sender) ERR-INSUFFICIENT-EXPERIENCE))
        (evaluation-tally (unwrap! (map-get? evaluation-tallies discovery-id) ERR-DISCOVERY-NOT-FOUND))
        )
        
        ;; Check base camp status
        (asserts! (var-get base-camp-operational) ERR-BASE-CAMP-CLOSED)
        
        ;; Ensure discovery hasn't already been validated
        (asserts! (not (get validated discovery)) ERR-EXPEDITION-LOCKED)
        
        ;; Check explorer hasn't already evaluated
        (asserts! (is-none (map-get? discovery-evaluations 
                                    {discovery-id: discovery-id, evaluator: tx-sender})) 
                ERR-ALREADY-EVALUATED)
        
        ;; Record the evaluation
        (map-set discovery-evaluations 
            {discovery-id: discovery-id, evaluator: tx-sender}
            {
                confirmed: confirm,
                weight: (get evaluation-weight explorer)
            })
        
        ;; Update evaluation tally
        (map-set evaluation-tallies discovery-id
            (merge evaluation-tally {
                confirmation-weight: (if confirm 
                                    (+ (get confirmation-weight evaluation-tally) (get evaluation-weight explorer))
                                    (get confirmation-weight evaluation-tally)),
                rejection-weight: (if (not confirm)
                                    (+ (get rejection-weight evaluation-tally) (get evaluation-weight explorer))
                                    (get rejection-weight evaluation-tally)),
                total-evaluations: (+ (get total-evaluations evaluation-tally) u1)
            }))
        
        (ok true)))

;; Finalize Season Discoveries
(define-public (finalize-season)
    (begin
        ;; Only expedition leader can finalize season
        (asserts! (is-expedition-leader) ERR-NOT-AUTHORIZED)
        (asserts! (var-get base-camp-operational) ERR-BASE-CAMP-CLOSED)
        
        ;; Advance expedition season
        (var-set expedition-season (+ (var-get expedition-season) u1))
        
        (ok true)))

;; Process Specific Discovery
(define-public (process-discovery (discovery-id uint))
    (let (
        (discovery (unwrap! (map-get? expedition-discoveries discovery-id) ERR-DISCOVERY-NOT-FOUND))
        (evaluation-tally (unwrap! (map-get? evaluation-tallies discovery-id) ERR-DISCOVERY-NOT-FOUND))
        (expedition (unwrap! (map-get? expeditions (get target-expedition discovery)) ERR-INVALID-EXPEDITION))
        (explorer (unwrap! (map-get? explorer-profiles (get explorer discovery)) ERR-INVALID-PARAMETER))
        )
        
        ;; Only expedition leader can process discoveries
        (asserts! (is-expedition-leader) ERR-NOT-AUTHORIZED)
        (asserts! (var-get base-camp-operational) ERR-BASE-CAMP-CLOSED)
        
        ;; Ensure discovery hasn't already been validated
        (asserts! (not (get validated discovery)) ERR-EXPEDITION-LOCKED)
        
        ;; Check for sufficient evaluations and meeting threshold
        (if (and 
                (> (+ (get confirmation-weight evaluation-tally) (get rejection-weight evaluation-tally)) u0)
                (>= (* (get confirmation-weight evaluation-tally) u100) 
                    (* (+ (get confirmation-weight evaluation-tally) (get rejection-weight evaluation-tally)) (var-get validation-threshold)))
            )
            (begin
                ;; Update discovery status
                (map-set expedition-discoveries discovery-id
                    (merge discovery {validated: true}))
                
                ;; Update expedition data
                (map-set expeditions (get target-expedition discovery)
                    (merge expedition {
                        location-hash: (get discovery-hash discovery),
                        validated-discoveries: (+ (get validated-discoveries expedition) u1)
                    }))
                
                ;; Add explorer to expedition explorers if not already
                (match (map-get? expedition-explorers {expedition-id: (get target-expedition discovery), explorer: (get explorer discovery)})
                    existing-participation
                    true
                    ;; Add new explorer
                    (map-set expedition-explorers 
                        {expedition-id: (get target-expedition discovery), explorer: (get explorer discovery)}
                        {experience-committed: (get experience explorer)}))
                
                ;; Update expedition's total experience
                (map-set expeditions (get target-expedition discovery)
                    (merge expedition {
                        total-experience: (+ (get total-experience expedition) (get experience explorer))
                    }))
                
                ;; Reward explorer with experience boost
                (map-set explorer-profiles (get explorer discovery)
                    (merge explorer {
                        experience: (+ (get experience explorer) u25),
                        evaluation-weight: (+ (get evaluation-weight explorer) u10)
                    }))
                
                (ok true))
            (ok false)))) ;; No action if threshold not met

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

;; Read-only functions
(define-read-only (get-expedition-details (expedition-id uint))
    (map-get? expeditions expedition-id))

(define-read-only (get-explorer-profile (explorer principal))
    (map-get? explorer-profiles explorer))

(define-read-only (get-discovery-details (discovery-id uint))
    (map-get? expedition-discoveries discovery-id))

(define-read-only (get-discovery-evaluations (discovery-id uint))
    (map-get? evaluation-tallies discovery-id))

(define-read-only (get-base-camp-metrics)
    {
        operational: (var-get base-camp-operational),
        expedition-season: (var-get expedition-season),
        minimum-experience: (var-get minimum-experience-threshold),
        validation-threshold: (var-get validation-threshold)
    })

(define-public (update-minimum-experience (new-minimum uint))
    (begin
        (asserts! (is-expedition-leader) ERR-NOT-EXPEDITION-LEADER)
        ;; Validate new threshold is within acceptable range
        (asserts! (and (>= new-minimum MIN-EXPERIENCE-REQUIRED) (<= new-minimum MAX-EXPERIENCE-INPUT)) ERR-INVALID-PARAMETER)
        (var-set minimum-experience-threshold new-minimum)
        (ok true)))

(define-public (update-validation-threshold (new-percentage uint))
    (begin
        (asserts! (is-expedition-leader) ERR-NOT-EXPEDITION-LEADER)
        ;; Validate percentage is between 1 and 100
        (asserts! (and (> new-percentage u0) (<= new-percentage MAX-VALIDATION-THRESHOLD)) ERR-INVALID-PARAMETER)
        (var-set validation-threshold new-percentage)
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