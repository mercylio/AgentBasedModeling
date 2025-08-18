;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Simulation of Public Opinion and Adoption in Integrated Digital ID Rollouts
;; Two-stage behavioral process: Opinion Dynamics → Collective Action
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SECTION: Global Declarations
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

extensions [csv]

globals [
  ;; CSV management
  demo-data

  ;; Scenario control
  ;political-scenario
  max-od-ticks
  od-end-tick
  adoption-rate
  ;memory-decay-rate
  ;population-size
  institutional-credibility
  current-stage
  od-completed?
  ca-initiated?

  ;; Aggregates and metrics
  avg-trust avg-surveillance avg-inclusion avg-memory
  std-trust std-surveillance std-inclusion
  total-enrolled total-resisted total-undecided
  cascade-size-this-tick resistance-rate
  entropy-trust entropy-surveillance entropy-inclusion

  ;; Random Seed for Shock Robustness Check
  seed
]

turtles-own [
  ;; Demographics and traits
  district location-type ses-type
  digital-literacy vulnerability impressionability

  ;; OD state
  opinion-trust opinion-surveillance opinion-inclusion
  memory-score

  ;; CA state
  opinion-score memory-of-exclusion action-state
  peer-influence

  ;; Thresholds
  trust-threshold surveillance-threshold inclusion-threshold ;social-threshold
]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SECTION: Main Control Procedures
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to go
  if current-stage = "opinion-dynamics" [
    run-opinion-dynamics
  ]
  if current-stage = "collective-action" [
    run-collective-action
  ]
  update-global-metrics
end

to go-od-only
  if not od-completed? [
    while [not od-completed? and ticks < max-od-ticks] [
      run-opinion-dynamics
    ]
  ]
;  if ticks >= max-od-ticks or opinion-stabilized? [
;  set od-completed? true
;  ;transition-to-collective-action ;; optional here if running automatically
;  ]
  if opinion-stabilized? [
  set od-completed? true
  ;transition-to-collective-action ;; optional here if running automatically
  ]
end

to go-ca-only
  if not od-completed? [
    user-message "Opinion Dynamics must complete before Collective Action."
    stop
  ]
  if od-completed? and not ca-initiated?[
    ;; If CA hasn't started yet, transition
    transition-to-collective-action
  ]
  if ca-initiated? [
    ;; Run CA phase
    while [ticks < max-od-ticks + 100] [
      run-collective-action
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SECTION: Initialisation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to setup
  clear-all
  set max-od-ticks -1
  set od-end-tick -1
  set current-stage "opinion-dynamics"
  set od-completed? false
  set ca-initiated? false

  ;; Set scenario-specific parameters
  set-scenario-parameters

  ;; Load demographic CSV
  let raw csv:from-file "aadhaar_march25enrolment_enriched.csv"
  set demo-data but-first raw  ;; remove headers

  generate-agents

  ;; Build small-world-like network (4–6 neighbors)
  form-initial-network

  random-seed seed

  reset-ticks
end

to generate-agents
  let total-agents population-size

  ;; compute row weights based on enrollment size (e.g., Age_18+)
  ;let agg-weights map [row -> read-from-string item 6 row] demo-data
  let agg-weights map [row -> item 6 row] demo-data
  let total-weight sum agg-weights

  repeat total-agents [
    ;; Sample a row with probability proportional to enrollment
    let sampled-row weighted-one-of demo-data agg-weights

    create-turtles 1 [
      setxy random-xcor random-ycor

      let district-val item 2 sampled-row
      let location-val item 7 sampled-row
      let ses-val item 8 sampled-row
      let d-literacy-val item 10 sampled-row

      set district district-val
      set location-type location-val
      set ses-type ses-val
      set digital-literacy d-literacy-val
      set vulnerability compute-vulnerability ses-type digital-literacy
      set impressionability 0.5 - (vulnerability * 0.2) + random-normal 0 0.05
      initialize-opinions
      set memory-score vulnerability * 0.2 + random-float 0.1
      set action-state "undecided"
      assign-thresholds
    ]
  ]
end

to initialize-opinions
  ;; Initialize based on vulnerability and random variation
;  set opinion-trust bound-opinion (0.5 - vulnerability * 0.3 + random-normal 0 0.15)
;  set opinion-surveillance bound-opinion (0.5 + vulnerability * 0.2 + random-normal 0 0.15)
;  set opinion-inclusion bound-opinion (0.5 - vulnerability * 0.2 + random-normal 0 0.15)
  ;; Make opinions centered more around 0.4–0.6 rather than near 1
  let base-trust 0.4 + random-float 0.2  ; 0.4 to 0.6
  let base-surveillance 0.4 + random-float 0.2
  let base-inclusion 0.4 + random-float 0.2

  ;; Adjust further by vulnerability (small influence)
  set opinion-trust bound-opinion (base-trust - vulnerability * 0.1)
  set opinion-surveillance bound-opinion (base-surveillance + vulnerability * 0.1)
  set opinion-inclusion bound-opinion (base-inclusion - vulnerability * 0.1)
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SUB-SECTION: Scenario Parameters and Thresholds
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to set-scenario-parameters
  if political-scenario = "Technocratic-India" [
    set adoption-rate 0.95
    set memory-decay-rate 0.01
    set institutional-credibility 0.9
    ;set shock-severity 0.3
    ;set max-od-ticks 60
  ]
  if political-scenario = "Democratic-Optional" [
    set adoption-rate 0.3
    set memory-decay-rate 0.02
    set institutional-credibility 0.6
    ;set shock-severity 0.6
    ;set max-od-ticks 80
  ]
  if political-scenario = "Populist-Sceptical" [
    set adoption-rate 0.2
    set memory-decay-rate 0.03
    set institutional-credibility 0.5
    ;set shock-severity 0.85
    ;set max-od-ticks 100
  ]
  if political-scenario = "Authoritarian-Enforced" [
    set adoption-rate 0.75
    set memory-decay-rate 0.005
    set institutional-credibility 1.0
    ;set shock-severity 0.75
    ;set max-od-ticks 50
  ]
end

;to assign-thresholds
;  set trust-threshold random-normal 0.5 0.1
;  set surveillance-threshold random-normal 0.5 0.1
;  set inclusion-threshold random-normal 0.5 0.1
;  set social-threshold random-normal 0.5 0.1
;  ;set social-threshold min (list social-threshold 0.6)
;end

to assign-thresholds
  let offset 0
  if political-scenario = "Technocratic-India"     [ set offset -0.05 ]
  if political-scenario = "Democratic-Optional"    [ set offset  0.00 ]
  if political-scenario = "Populist-Sceptical"     [ set offset  0.05 ]
  if political-scenario = "Authoritarian-Enforced" [ set offset  0.10 ]

  set trust-threshold        bound-opinion (random-normal (0.50 + offset) 0.08)
  set surveillance-threshold bound-opinion (random-normal (0.50 - offset) 0.08)
  set inclusion-threshold    bound-opinion (random-normal (0.50 + offset) 0.08)
  set social-threshold       bound-opinion (random-normal (0.50 + offset) 0.07)
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SUB-SECTION: Network Formation/Evolution
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;to form-initial-network
;  ask turtles [
;    let same-ses other turtles with [ses-type = [ses-type] of myself]
;    let local-partners n-of 4 same-ses with [not link-neighbor? myself]
;    create-links-with local-partners
;
;    ;; add random long-range tie (rewiring)
;    if random-float 1 < 0.2 [
;      let distant-partner one-of other turtles with [not link-neighbor? myself and self != myself]
;      if distant-partner != nobody [ create-link-with distant-partner ]
;    ]
;  ]
;
;  ;; fix isolated turtles
;  ask turtles with [count link-neighbors = 0] [
;    create-link-with one-of other turtles
;  ]
;end

to form-initial-network
  ;; Create small-world network with SES clustering
  ask turtles [
    ;let target-neighbors 5
    let target-neighbors target-neighbor
    let same-ses other turtles with [ses-type = [ses-type] of myself]

    ;; Connect to local SES peers
;    if count same-ses >= target-neighbors [
;      let local-partners n-of target-neighbors same-ses with [not link-neighbor? myself]
;      create-links-with local-partners
;    ]
    let eligible-partners same-ses with [not link-neighbor? myself]
    if any? eligible-partners [
      let n min (list target-neighbors count eligible-partners)
      let local-partners n-of n eligible-partners
      create-links-with local-partners
    ]

    ;; Add random long-range tie (rewiring for small-world property)
    if random-float 1 < 0.15 [
      let distant-partner one-of other turtles with [not link-neighbor? myself and self != myself]
      if distant-partner != nobody [
        create-link-with distant-partner
      ]
    ]
  ]

  ;; Fix isolated agents
  ask turtles with [count link-neighbors = 0] [
    let nearest one-of other turtles
    if nearest != nobody [
      create-link-with nearest
    ]
  ]
end

;to evolve-network
;  ;; Break links with agents who have diverged too much in opinion
;  ask links [
;    let agent1 end1
;    let agent2 end2
;    let opinion-distance sqrt (([opinion-trust] of agent1 - [opinion-trust] of agent2) ^ 2 +
;                              ([opinion-surveillance] of agent1 - [opinion-surveillance] of agent2) ^ 2 +
;                              ([opinion-inclusion] of agent1 - [opinion-inclusion] of agent2) ^ 2)
;    if opinion-distance > 0.7 [  ; Threshold for link breaking
;      die
;    ]
;  ]
;
;  ;; Form new links with similar agents
;  ask turtles [
;    if count link-neighbors < 3 and random-float 1 < 0.1 [
;      let similar-agents other turtles with [not link-neighbor? myself]
;      if any? similar-agents [
;        let potential-partner min-one-of similar-agents [
;          sqrt ((opinion-trust - [opinion-trust] of myself) ^ 2 +
;                (opinion-surveillance - [opinion-surveillance] of myself) ^ 2 +
;                (opinion-inclusion - [opinion-inclusion] of myself) ^ 2)
;        ]
;        if potential-partner != nobody [
;          create-link-with potential-partner
;        ]
;      ]
;    ]
;  ]
;end

to evolve-opinion-network
  ask links [
    let d calculate-opinion-distance end1 end2
    if d > 0.6 [ die ]  ;; cut weak ties
  ]

  ask turtles [
    if count link-neighbors < 4 [
      let candidates other turtles with [
        not link-neighbor? myself and
        ses-type = [ses-type] of myself and
        calculate-opinion-distance myself self <= 0.5
      ]
      if any? candidates [
        create-link-with one-of candidates
      ]
    ]
  ]
end

to evolve-action-network
  ask links [
    if [action-state] of end1 != [action-state] of end2 and
       [action-state] of end1 != "undecided" and
       [action-state] of end2 != "undecided" [
      if random-float 1 < 0.3 [ die ]
    ]
  ]

  ask turtles with [count link-neighbors < 6 and action-state != "undecided"] [
    let candidates other turtles with [
      not link-neighbor? myself and
      action-state = [action-state] of myself
    ]
    if any? candidates [
      create-link-with one-of candidates
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SECTION: Opinion Dynamics (OD) Phase
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to run-opinion-dynamics
  if current-stage != "opinion-dynamics" [ stop ]

  ;; Institutional broadcast
  if random-float 1 < 0.2 [
    ask turtles [
      let receptivity institutional-credibility * (1 - memory-score) * impressionability
      set opinion-trust bound-opinion (opinion-trust + receptivity * 0.05)
      set opinion-inclusion bound-opinion (opinion-inclusion + receptivity * 0.04)
      set opinion-surveillance bound-opinion (opinion-surveillance - receptivity * 0.03)
    ]
  ]

  ;; Shock event (e.g. exclusion or data breach)
  maybe-trigger-institutional-shock

  ;; Peer influence (bounded confidence model)
  ask turtles [
    if any? link-neighbors [
      let peer one-of link-neighbors
      let opinion-distance sqrt ((opinion-trust - [opinion-trust] of peer) ^ 2 +
                         (opinion-surveillance - [opinion-surveillance] of peer) ^ 2 +
                         (opinion-inclusion - [opinion-inclusion] of peer) ^ 2)
      if opinion-distance < 0.5 [
        let weight (1 - memory-score) * impressionability * 0.2
        set opinion-trust bound-opinion (opinion-trust + weight * ([opinion-trust] of peer - opinion-trust))
        set opinion-surveillance bound-opinion (opinion-surveillance + weight * ([opinion-surveillance] of peer - opinion-surveillance))
        set opinion-inclusion bound-opinion (opinion-inclusion + weight * ([opinion-inclusion] of peer - opinion-inclusion))
      ]
    ]
  ]

    ;; Add network evolution every 10 ticks
    if ticks mod 10 = 0 [
      evolve-opinion-network
    ]
  ;; Memory decay
  ask turtles [
    set memory-score max (list 0 (memory-score - memory-decay-rate))
  ]

  ;; Check for OD completion
;  if ticks >= max-od-ticks or opinion-stabilized? [
;    set od-completed? true
;    transition-to-collective-action
;  ]
  if opinion-stabilized? [
  set od-end-tick ticks
  set od-completed? true
  transition-to-collective-action
  ]

  tick
end

;to maybe-trigger-institutional-shock
;  ;; Trigger logic depends on current resistance or credibility
;  if resistance-rate > 0.3 and random-float 1 < 0.2 [
;    apply-institutional-shock "exclusion"
;  ]
;  if institutional-credibility < 0.4 and random-float 1 < 0.1 [
;    apply-institutional-shock "enforcement"
;  ]
;  if avg-surveillance > 0.7 and random-float 1 < 0.1 [
;    apply-institutional-shock "leak"
;  ]
;end
to maybe-trigger-institutional-shock
  ;; multiply them by the slider so severity = 0 means never
  if resistance-rate > 0.30 and random-float 1 < 0.20 * shock-severity [
    apply-institutional-shock "exclusion"
  ]
  if institutional-credibility < 0.40 and random-float 1 < 0.10 * shock-severity [
    apply-institutional-shock "enforcement"
  ]
  if avg-surveillance > 0.70 and random-float 1 < 0.10 * shock-severity [
    apply-institutional-shock "leak"
  ]
end

to apply-institutional-shock [shock-type]
  let shock shock-severity
  ask turtles [
    let impact (vulnerability + random-float 0.2) * shock-severity

    if shock-type = "exclusion" [
      set opinion-inclusion bound-opinion (opinion-inclusion - impact * 0.8)
      set opinion-trust bound-opinion (opinion-trust - impact * 0.4)
      set memory-score min (list 1 (memory-score + impact * 0.6))
    ]

    if shock-type = "leak" [
      set opinion-surveillance bound-opinion (opinion-surveillance + impact * 0.7)
      set opinion-trust bound-opinion (opinion-trust - impact * 0.6)
      set memory-score min (list 1 (memory-score + impact * 0.5))
    ]

    if shock-type = "enforcement" and political-scenario = "Authoritarian-Enforced" [
      set opinion-surveillance bound-opinion (opinion-surveillance + 0.9)
      set opinion-trust bound-opinion (opinion-trust - 0.5)
      set memory-score min (list 1 (memory-score + 0.4))
    ]
  ]

  ;; Adjust credibility as feedback
  if shock-type = "exclusion" or shock-type = "leak" [
    set institutional-credibility max list 0.05 (institutional-credibility - 0.03 * shock-severity)
  ]
end

to-report opinion-stabilized?
  let delta (standard-deviation [opinion-trust] of turtles +
             standard-deviation [opinion-surveillance] of turtles +
             standard-deviation [opinion-inclusion] of turtles)

  ;; Also check if change rate is very slow
  let avg-change abs(avg-trust - (sum [opinion-trust] of turtles / count turtles))

  ;report (delta < 0.05 and avg-change < 0.01) or ticks > max-od-ticks
  report (delta < 0.05 and avg-change < 0.01)
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SECTION: Transition to Collective Action
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to transition-to-collective-action
  if not od-completed? or ca-initiated? [ stop ]
  ;set max-od-ticks ticks ; Store when OD completed
  set od-end-tick ticks
  recompute-opinion-scores
  ask turtles [
;    let raw-score (0.4 * opinion-trust + 0.3 * (1 - opinion-surveillance) + 0.3 * opinion-inclusion)
;    let normalized-score (raw-score - 0.3) / (0.9 - 0.3)
;    set opinion-score bound-opinion normalized-score
    ;set opinion-score (0.4 * opinion-trust + 0.3 * opinion-surveillance + 0.3 * opinion-inclusion)
    set memory-of-exclusion memory-score
  ]
  seed-early-enrollers
  seed-early-resisters
  set current-stage "collective-action"
  set ca-initiated? true
end

to seed-early-enrollers
  ask turtles with [
    opinion-score > 0.7 and
    opinion-trust > trust-threshold and
    opinion-surveillance < surveillance-threshold and
    opinion-inclusion > inclusion-threshold
  ] [
    if random-float 1 < adoption-rate [
      set action-state "enrolled"
    ]
  ]
end

to seed-early-resisters
  ask turtles with [
    opinion-score < 0.3 or memory-score > 0.6
  ] [
    if random-float 1 < 0.2 [
      set action-state "resisted"
    ]
  ]
end

to recompute-opinion-scores
  ;; --- raw score for every agent
  ask turtles [
    set opinion-score 0.4 * opinion-trust +
                      0.3 * (1 - opinion-surveillance) +
                      0.3 * opinion-inclusion
  ]

  ;; --- min–max rescale inside [0 1] for this run
  let min-raw min [opinion-score] of turtles
  let max-raw max [opinion-score] of turtles
  let span max-raw - min-raw
  if span = 0 [ set span 1 ]          ;; safeguard for zero variance

  ask turtles [
    set opinion-score (opinion-score - min-raw) / span
  ]

  ;; --- scenario-specific bias
  let bias 0
  if political-scenario = "Technocratic-India"     [ set bias  0.10 ]
  if political-scenario = "Democratic-Optional"    [ set bias  0.00 ]
  if political-scenario = "Populist-Sceptical"     [ set bias -0.05 ]
  if political-scenario = "Authoritarian-Enforced" [ set bias  0.15 ]

  ask turtles [
    set opinion-score bound-opinion (opinion-score + bias)
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SECTION: Collective Action (CA) Phase
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to run-collective-action
  if current-stage != "collective-action" [ stop ]
  set cascade-size-this-tick 0

  update-peer-influence
  update-action-decisions
  update-institutional-credibility

  ;; Add network evolution every 5 ticks
  if ticks mod 5 = 0 [
    evolve-action-network
  ]

  ;; decay memory
  ask turtles [
    set memory-of-exclusion max (list 0 (memory-of-exclusion - memory-decay-rate))
  ]

  tick
end

to update-peer-influence
  ask turtles [
    let near-neighbors link-neighbors
    if any? near-neighbors [
      let enrolled-neighbors count near-neighbors with [action-state = "enrolled"]
      let resisted-neighbors count near-neighbors with [action-state = "resisted"]
      let total-neighbors count near-neighbors

      if total-neighbors > 0 [
        set peer-influence (enrolled-neighbors - resisted-neighbors) / total-neighbors
      ]
    ]
  ]
end

to update-action-decisions
  ask turtles with [action-state = "undecided"] [
    let enroll-pressure opinion-score + (peer-influence * 0.3) + (institutional-credibility * 0.2)
    let resist-pressure memory-of-exclusion + (max (list 0 (- peer-influence))) * 0.4 + ((1 - institutional-credibility) * 0.3)

    if abs (enroll-pressure - resist-pressure) < 0.1 [
      ;; too close to decide — remain undecided
    ]
;    if opinion-trust > trust-threshold and opinion-surveillance < surveillance-threshold and opinion-inclusion > inclusion-threshold [
;      if enroll-pressure > social-threshold [
;        set action-state "enrolled"
;        set cascade-size-this-tick cascade-size-this-tick + 1
;      ]
;    ]
    if opinion-score > 0.6 and enroll-pressure > social-threshold and enroll-pressure > resist-pressure [
      set action-state "enrolled"
      set cascade-size-this-tick cascade-size-this-tick + 1
    ]
    if opinion-score < 0.4 and resist-pressure > social-threshold and resist-pressure > enroll-pressure [
      set action-state "resisted"
      set cascade-size-this-tick cascade-size-this-tick + 1
    ]
  ]

  ;; Allow resisters to switch to enrollment
  ask turtles with [action-state = "resisted"] [
    let enroll-pressure opinion-score + (peer-influence * 0.5) + (institutional-credibility * 0.3)

    ;; Strong peer pressure can convert resistance but Enrolled agents generally stay enrolled
    ;if peer-influence > 0.6 and enroll-pressure > (social-threshold + 0.3) [
    ;  if random-float 1 < 0.05 [  ; 8% chance per tick when conditions met
    if peer-influence > 0.4 and enroll-pressure > (social-threshold + 0.1) [
      if random-float 1 < 0.1 [  ; 10% chance per tick when conditions met
        set action-state "enrolled"
        set cascade-size-this-tick cascade-size-this-tick + 1
      ]
    ]
  ]
end

to update-institutional-credibility
  let current-resistance-rate count turtles with [action-state = "resisted"] / count turtles
  set resistance-rate current-resistance-rate
  if resistance-rate > 0.3 [
    set institutional-credibility max (list 0 (institutional-credibility - 0.01))
  ]
  if resistance-rate < 0.1 [
    set institutional-credibility min (list 1 (institutional-credibility + 0.005))
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SECTION: Calculate Metrics
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to update-global-metrics
  ;; Opinion metrics
  set avg-trust mean [opinion-trust] of turtles
  set avg-surveillance mean [opinion-surveillance] of turtles
  set avg-inclusion mean [opinion-inclusion] of turtles
  set avg-memory mean [memory-score] of turtles

  ;; Opinion polarization (standard deviations)
  set std-trust standard-deviation [opinion-trust] of turtles
  set std-surveillance standard-deviation [opinion-surveillance] of turtles
  set std-inclusion standard-deviation [opinion-inclusion] of turtles

  ;; Action state counts
  set total-enrolled count turtles with [action-state = "enrolled"]
  set total-resisted count turtles with [action-state = "resisted"]
  set total-undecided count turtles with [action-state = "undecided"]

  ;; Entropy calculations for opinion diversity
  set entropy-trust calculate-entropy [opinion-trust] of turtles
  set entropy-surveillance calculate-entropy [opinion-surveillance] of turtles
  set entropy-inclusion calculate-entropy [opinion-inclusion] of turtles
end

to-report calculate-entropy [opinion-list]
  ;; Simple entropy calculation for opinion distribution
  let bins 10
  let counts n-values bins [0]

  foreach opinion-list [
    opinion ->
    let bin-index floor (opinion * (bins - 0.001))  ; Avoid index 10
    set bin-index max (list 0 (min (list (bins - 1) bin-index)))
    set counts replace-item bin-index counts (item bin-index counts + 1)
  ]

  let total length opinion-list
  let entropy 0
  foreach counts [
    one-count ->
    if one-count > 0 [
      let probability one-count / total
      ;set entropy entropy - (probability * ln probability)
      set entropy entropy - (probability * log probability 2)

    ]
  ]

  report entropy
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SECTION: Output & Reporting
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to-report weighted-one-of [data weight-list]
  let r random-float (sum weight-list)
  let i 0
  let acc 0
  while [i < length data] [
    set acc acc + item i weight-list
    if acc >= r [ report item i data ]
    set i i + 1
  ]
  report last data  ;; fallback
end

to-report bound-opinion [val]
  report max (list 0 (min (list 1 val)))
end

to-report compute-vulnerability [ses lit]
  if ses = "low" [ report (0.8 + (1 - lit)) / 2 ]
  if ses = "medium" [ report (0.5 + (1 - lit)) / 2 ]
  if ses = "high" [ report (0.3 + (1 - lit)) / 2 ]
end

to-report calculate-opinion-distance [agent1 agent2]
  let trust-diff abs ([opinion-trust] of agent1 - [opinion-trust] of agent2)
  let surveillance-diff abs ([opinion-surveillance] of agent1 - [opinion-surveillance] of agent2)
  let inclusion-diff abs ([opinion-inclusion] of agent1 - [opinion-inclusion] of agent2)

  ;; Euclidean distance normalized across 3 dimensions
  let euc-distance sqrt (trust-diff ^ 2 + surveillance-diff ^ 2 + inclusion-diff ^ 2)
  ;; Normalize Euclidean distance across 3D opinion space
  report euc-distance / sqrt 3
end

to-report rate-enrollment
   ifelse count turtles > 0
  [ report count turtles with [action-state = "enrolled"] / count turtles ]
  [ report 0 ]
end

to-report rate-resistance
   ifelse count turtles > 0
  [ report count turtles with [action-state = "resisted"] / count turtles ]
  [ report 0 ]
end

to-report rate-undecided
  ifelse count turtles > 0
  [ report count turtles with [action-state = "undecided"] / count turtles ]
  [ report 0 ]
end

to-report opinion-polarization
  report (std-trust + std-surveillance + std-inclusion) / 3
end

to-report network-density
  let total-possible-links (count turtles * (count turtles - 1)) / 2
  if total-possible-links > 0 [
    report count links / total-possible-links
  ]
  report 0
end

to-report cascade-size
  report cascade-size-this-tick
end

to-report current-institutional-credibility
  report institutional-credibility
end

to-report memory-histogram
  ;; Return memory distribution for analysis
  report [memory-score] of turtles
end

to-report opinion-vectors
  ;; Return all opinion vectors for detailed analysis
  let results []
  ask turtles [
    set results lput (list opinion-trust opinion-surveillance opinion-inclusion) results
  ]
  report results
end

to-report ses-breakdown-e
  ;; Report enrollment by SES category
  let low-ses-enrolled count turtles with [ses-type = "low" and action-state = "enrolled"]
  let low-ses-total count turtles with [ses-type = "low"]
  ifelse low-ses-total > 0
    [ report low-ses-enrolled / low-ses-total ]
    [ report 0 ]
end

to-report ses-breakdown-enrollment
  let low-ses count turtles with [ses-type = "low"]
  let med-ses count turtles with [ses-type = "medium"]
  let high-ses count turtles with [ses-type = "high"]

  let low-enrolled count turtles with [ses-type = "low" and action-state = "enrolled"]
  let med-enrolled count turtles with [ses-type = "medium" and action-state = "enrolled"]
  let high-enrolled count turtles with [ses-type = "high" and action-state = "enrolled"]

  let low-ratio ifelse-value low-ses > 0 [ low-enrolled / low-ses ] [ 0 ]
  let med-ratio ifelse-value med-ses > 0 [ med-enrolled / med-ses ] [ 0 ]
  let high-ratio ifelse-value high-ses > 0 [ high-enrolled / high-ses ] [ 0 ]

  report (list low-ratio med-ratio high-ratio)
end

to-report ses-breakdown-resistance
  let low-ses count turtles with [ses-type = "low"]
  let med-ses count turtles with [ses-type = "medium"]
  let high-ses count turtles with [ses-type = "high"]

  let low-resist count turtles with [ses-type = "low" and action-state = "resisted"]
  let med-resist count turtles with [ses-type = "medium" and action-state = "resisted"]
  let high-resist count turtles with [ses-type = "high" and action-state = "resisted"]

  let low-ratio ifelse-value low-ses > 0 [ low-resist / low-ses ] [ 0 ]
  let med-ratio ifelse-value med-ses > 0 [ med-resist / med-ses ] [ 0 ]
  let high-ratio ifelse-value high-ses > 0 [ high-resist / high-ses ] [ 0 ]

  report (list low-ratio med-ratio high-ratio)
end

to-report ses-breakdown-undecided
  let low-ses count turtles with [ses-type = "low"]
  let med-ses count turtles with [ses-type = "medium"]
  let high-ses count turtles with [ses-type = "high"]

  let low-resist count turtles with [ses-type = "low" and action-state = "undecided"]
  let med-resist count turtles with [ses-type = "medium" and action-state = "undecided"]
  let high-resist count turtles with [ses-type = "high" and action-state = "undecided"]

  let low-ratio ifelse-value low-ses > 0 [ low-resist / low-ses ] [ 0 ]
  let med-ratio ifelse-value med-ses > 0 [ med-resist / med-ses ] [ 0 ]
  let high-ratio ifelse-value high-ses > 0 [ high-resist / high-ses ] [ 0 ]

  report (list low-ratio med-ratio high-ratio)
end

to-report digital-divide-effect
  ;; Compare enrollment between literate and illiterate
  let literate-enrolled count turtles with [digital-literacy = 1 and action-state = "enrolled"]
  let literate-total count turtles with [digital-literacy = 1]
  let illiterate-enrolled count turtles with [digital-literacy = 0 and action-state = "enrolled"]
  let illiterate-total count turtles with [digital-literacy = 0]

  let lit-rate ifelse-value (literate-total > 0) [literate-enrolled / literate-total] [0]
  let illit-rate ifelse-value (illiterate-total > 0) [illiterate-enrolled / illiterate-total] [0]

  report lit-rate - illit-rate  ; Positive = literacy advantage
end

to-report time-to-stabilization
  ;; How long did OD phase take?
  if od-completed? [ report max-od-ticks ]
  report -1  ; Not yet stabilized
end

to-report time-of-ca-start
  ;; When CA phase began
  if ca-initiated? [
    report max-od-ticks  ; Same as OD end
  ]
  report -1
end

to-report od-duration
;  if od-completed? [
;    report max-od-ticks  ; When it actually completed
;  ]
  if od-end-tick > -1 [report od-end-tick]
  report ticks  ; Still running
end

to-report ca-duration
  if ca-initiated? [
    report ticks - od-duration
  ]
  report 0
end

to-report total-simulation-time
  report ticks
end
@#$#@#$#@
GRAPHICS-WINDOW
210
10
647
448
-1
-1
13.0
1
10
1
1
1
0
1
1
1
-16
16
-16
16
0
0
1
ticks
30.0

BUTTON
3
10
66
43
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
69
10
132
43
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
135
10
199
43
go-od
go-od-only
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
202
10
265
43
go-ca
go-ca-only
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
4
80
176
113
memory-decay-rate
memory-decay-rate
0.001
0.05
0.05
0.001
1
NIL
HORIZONTAL

CHOOSER
4
185
182
230
political-scenario
political-scenario
"Technocratic-India" "Democratic-Optional" "Populist-Sceptical" "Authoritarian-Enforced"
0

SLIDER
4
150
176
183
confidence-threshold
confidence-threshold
0.1
1
0.5
0.05
1
NIL
HORIZONTAL

SLIDER
4
357
176
390
broadcast-frequency
broadcast-frequency
0.1
1
1.0
0.01
1
NIL
HORIZONTAL

SLIDER
5
393
177
426
shock-frequency
shock-frequency
0
1
0.0
0.01
1
NIL
HORIZONTAL

SLIDER
5
429
177
462
shock-severity
shock-severity
0.1
1
1.0
0.01
1
NIL
HORIZONTAL

SLIDER
4
115
176
148
social-threshold
social-threshold
0.1
1
1.0
0.01
1
NIL
HORIZONTAL

TEXTBOX
11
337
161
355
Advanced Settings (Optional)
11
0.0
1

MONITOR
655
19
806
64
Model Stage (OD or CA)
current-stage
17
1
11

PLOT
657
70
857
220
Opinion Dynamics (Avg)
Ticks
Value (0-1)
0.0
1.0
0.0
1.0
true
true
"" ""
PENS
"Trust" 1.0 0 -16777216 true "" "plot mean [opinion-trust] of turtles"
"Surveillance" 1.0 0 -13840069 true "" "plot mean [opinion-surveillance] of turtles"
"Inclusion" 1.0 0 -2674135 true "" "plot mean [opinion-inclusion] of turtles"

PLOT
872
69
1072
219
Adoption Over Time
Ticks
Proportion of Population
0.0
10.0
0.0
1.0
true
true
"" ""
PENS
"Enrolled" 1.0 0 -13840069 true "" "plot count turtles with [action-state = \"enrolled\"] / count turtles"
"Resisted" 1.0 0 -2674135 true "" "plot count turtles with [action-state = \"resisted\"] / count turtles"
"Undecided" 1.0 0 -1318182 true "" "plot count turtles with [action-state = \"undecided\"] / count turtles"

PLOT
762
233
962
383
Institutional Credibility
Ticks
Value (0 to 1)
0.0
10.0
0.0
1.0
true
true
"" ""
PENS
"Credibility" 1.0 0 -16777216 true "" "plot institutional-credibility"

SLIDER
4
45
176
78
population-size
population-size
1
2000
201.0
100
1
NIL
HORIZONTAL

SLIDER
5
465
177
498
target-neighbor
target-neighbor
1
10
10.0
1
1
NIL
HORIZONTAL

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="AllScenarioRuns" repetitions="50" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>od-completed? and ticks &gt;= od-end-tick + 200</exitCondition>
    <metric>rate-enrollment</metric>
    <metric>rate-resistance</metric>
    <metric>rate-undecided</metric>
    <metric>opinion-polarization</metric>
    <metric>current-institutional-credibility</metric>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>network-density</metric>
    <metric>cascade-size</metric>
    <metric>ses-breakdown-enrollment</metric>
    <metric>ses-breakdown-resistance</metric>
    <metric>ses-breakdown-undecided</metric>
    <metric>time-to-stabilization</metric>
    <metric>time-of-ca-start</metric>
    <metric>od-duration</metric>
    <metric>ca-initiated?</metric>
    <metric>ca-duration</metric>
    <metric>total-simulation-time</metric>
    <metric>count turtles with [action-state = "enrolled"]</metric>
    <metric>count turtles with [action-state = "resisted"]</metric>
    <metric>count turtles with [action-state = "undecided"]</metric>
    <enumeratedValueSet variable="political-scenario">
      <value value="&quot;Technocratic-India&quot;"/>
      <value value="&quot;Democratic-Optional&quot;"/>
      <value value="&quot;Populist-Skeptical&quot;"/>
      <value value="&quot;Authoritarian-Enforced&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="population-size">
      <value value="500"/>
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="memory-decay-rate">
      <value value="0.005"/>
      <value value="0.01"/>
      <value value="0.02"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Technocratic" repetitions="100" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>od-completed? and ticks &gt;= od-end-tick + 200</exitCondition>
    <metric>count turtles</metric>
    <metric>rate-enrollment</metric>
    <metric>rate-resistance</metric>
    <metric>rate-undecided</metric>
    <metric>opinion-polarization</metric>
    <metric>current-institutional-credibility</metric>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>cascade-size</metric>
    <metric>network-density</metric>
    <metric>time-to-stabilization</metric>
    <metric>ses-breakdown-enrollment</metric>
    <metric>ses-breakdown-resistance</metric>
    <metric>ses-breakdown-undecided</metric>
    <metric>digital-divide-effect</metric>
    <metric>time-of-ca-start</metric>
    <metric>od-duration</metric>
    <metric>ca-initiated?</metric>
    <metric>ca-duration</metric>
    <metric>total-simulation-time</metric>
    <metric>count turtles with [action-state = "enrolled"]</metric>
    <metric>count turtles with [action-state = "resisted"]</metric>
    <metric>count turtles with [action-state = "undecided"]</metric>
    <enumeratedValueSet variable="political-scenario">
      <value value="&quot;Technocratic-India&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="population-size">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Democratic" repetitions="100" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>od-completed? and ticks &gt;= od-end-tick + 200</exitCondition>
    <metric>count turtles</metric>
    <metric>rate-enrollment</metric>
    <metric>rate-resistance</metric>
    <metric>rate-undecided</metric>
    <metric>opinion-polarization</metric>
    <metric>current-institutional-credibility</metric>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>cascade-size</metric>
    <metric>network-density</metric>
    <metric>time-to-stabilization</metric>
    <metric>ses-breakdown-enrollment</metric>
    <metric>ses-breakdown-resistance</metric>
    <metric>ses-breakdown-undecided</metric>
    <metric>digital-divide-effect</metric>
    <metric>time-of-ca-start</metric>
    <metric>od-duration</metric>
    <metric>ca-initiated?</metric>
    <metric>ca-duration</metric>
    <metric>total-simulation-time</metric>
    <metric>count turtles with [action-state = "enrolled"]</metric>
    <metric>count turtles with [action-state = "resisted"]</metric>
    <metric>count turtles with [action-state = "undecided"]</metric>
    <enumeratedValueSet variable="political-scenario">
      <value value="&quot;Democratic-Optional&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="population-size">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Populist" repetitions="100" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>od-completed? and ticks &gt;= od-end-tick + 200</exitCondition>
    <metric>count turtles</metric>
    <metric>rate-enrollment</metric>
    <metric>rate-resistance</metric>
    <metric>rate-undecided</metric>
    <metric>opinion-polarization</metric>
    <metric>current-institutional-credibility</metric>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>cascade-size</metric>
    <metric>network-density</metric>
    <metric>time-to-stabilization</metric>
    <metric>ses-breakdown-enrollment</metric>
    <metric>ses-breakdown-resistance</metric>
    <metric>ses-breakdown-undecided</metric>
    <metric>digital-divide-effect</metric>
    <metric>time-of-ca-start</metric>
    <metric>od-duration</metric>
    <metric>ca-initiated?</metric>
    <metric>ca-duration</metric>
    <metric>total-simulation-time</metric>
    <metric>count turtles with [action-state = "enrolled"]</metric>
    <metric>count turtles with [action-state = "resisted"]</metric>
    <metric>count turtles with [action-state = "undecided"]</metric>
    <enumeratedValueSet variable="political-scenario">
      <value value="&quot;Populist-Skeptical&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="population-size">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Authoritarian" repetitions="100" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>od-completed? and ticks &gt;= od-end-tick + 200</exitCondition>
    <metric>count turtles</metric>
    <metric>rate-enrollment</metric>
    <metric>rate-resistance</metric>
    <metric>rate-undecided</metric>
    <metric>opinion-polarization</metric>
    <metric>current-institutional-credibility</metric>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>cascade-size</metric>
    <metric>network-density</metric>
    <metric>time-to-stabilization</metric>
    <metric>ses-breakdown-enrollment</metric>
    <metric>ses-breakdown-resistance</metric>
    <metric>ses-breakdown-undecided</metric>
    <metric>digital-divide-effect</metric>
    <metric>time-of-ca-start</metric>
    <metric>od-duration</metric>
    <metric>ca-initiated?</metric>
    <metric>ca-duration</metric>
    <metric>total-simulation-time</metric>
    <metric>count turtles with [action-state = "enrolled"]</metric>
    <metric>count turtles with [action-state = "resisted"]</metric>
    <metric>count turtles with [action-state = "undecided"]</metric>
    <enumeratedValueSet variable="political-scenario">
      <value value="&quot;Authoritarian-Enforced&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="population-size">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="PopulationSensitivity" repetitions="50" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>od-completed? and ticks &gt;= od-end-tick + 200</exitCondition>
    <metric>rate-enrollment</metric>
    <metric>rate-resistance</metric>
    <metric>rate-undecided</metric>
    <metric>opinion-polarization</metric>
    <metric>current-institutional-credibility</metric>
    <metric>time-to-stabilization</metric>
    <metric>cascade-size</metric>
    <metric>ses-breakdown-enrollment</metric>
    <metric>ses-breakdown-resistance</metric>
    <metric>ses-breakdown-undecided</metric>
    <metric>digital-divide-effect</metric>
    <metric>network-density</metric>
    <metric>od-duration</metric>
    <metric>ca-initiated?</metric>
    <metric>ca-duration</metric>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>count turtles with [action-state = "enrolled"]</metric>
    <metric>count turtles with [action-state = "resisted"]</metric>
    <metric>count turtles with [action-state = "undecided"]</metric>
    <enumeratedValueSet variable="political-scenario">
      <value value="&quot;Technocratic-India&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="population-size">
      <value value="250"/>
      <value value="500"/>
      <value value="1000"/>
      <value value="2000"/>
      <value value="4000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="MemoryDecaySensitivity" repetitions="50" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>od-completed? and ticks &gt;= od-end-tick + 200</exitCondition>
    <metric>rate-enrollment</metric>
    <metric>rate-resistance</metric>
    <metric>rate-undecided</metric>
    <metric>opinion-polarization</metric>
    <metric>current-institutional-credibility</metric>
    <metric>time-to-stabilization</metric>
    <metric>cascade-size</metric>
    <metric>ses-breakdown-enrollment</metric>
    <metric>ses-breakdown-resistance</metric>
    <metric>ses-breakdown-undecided</metric>
    <metric>digital-divide-effect</metric>
    <metric>network-density</metric>
    <metric>od-duration</metric>
    <metric>ca-initiated?</metric>
    <metric>ca-duration</metric>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>count turtles with [action-state = "enrolled"]</metric>
    <metric>count turtles with [action-state = "resisted"]</metric>
    <metric>count turtles with [action-state = "undecided"]</metric>
    <enumeratedValueSet variable="political-scenario">
      <value value="&quot;Technocratic-India&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="memory-decay-rate">
      <value value="0.001"/>
      <value value="0.005"/>
      <value value="0.01"/>
      <value value="0.02"/>
      <value value="0.03"/>
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="population-size">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="NetworkSensitivity" repetitions="50" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>od-completed? and ticks &gt;= od-end-tick + 200</exitCondition>
    <metric>rate-enrollment</metric>
    <metric>rate-resistance</metric>
    <metric>rate-undecided</metric>
    <metric>opinion-polarization</metric>
    <metric>current-institutional-credibility</metric>
    <metric>time-to-stabilization</metric>
    <metric>cascade-size</metric>
    <metric>ses-breakdown-enrollment</metric>
    <metric>ses-breakdown-resistance</metric>
    <metric>ses-breakdown-undecided</metric>
    <metric>digital-divide-effect</metric>
    <metric>network-density</metric>
    <metric>od-duration</metric>
    <metric>ca-initiated?</metric>
    <metric>ca-duration</metric>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>count turtles with [action-state = "enrolled"]</metric>
    <metric>count turtles with [action-state = "resisted"]</metric>
    <metric>count turtles with [action-state = "undecided"]</metric>
    <enumeratedValueSet variable="political-scenario">
      <value value="&quot;Technocratic-India&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="target-neighbor">
      <value value="2"/>
      <value value="3"/>
      <value value="5"/>
      <value value="7"/>
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="population-size">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="ThresholdSensitivity" repetitions="50" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>od-completed? and ticks &gt;= od-end-tick + 200</exitCondition>
    <metric>rate-enrollment</metric>
    <metric>rate-resistance</metric>
    <metric>rate-undecided</metric>
    <metric>opinion-polarization</metric>
    <metric>current-institutional-credibility</metric>
    <metric>time-to-stabilization</metric>
    <metric>cascade-size</metric>
    <metric>ses-breakdown-enrollment</metric>
    <metric>ses-breakdown-resistance</metric>
    <metric>ses-breakdown-undecided</metric>
    <metric>digital-divide-effect</metric>
    <metric>network-density</metric>
    <metric>od-duration</metric>
    <metric>ca-initiated?</metric>
    <metric>ca-duration</metric>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>count turtles with [action-state = "enrolled"]</metric>
    <metric>count turtles with [action-state = "resisted"]</metric>
    <metric>count turtles with [action-state = "undecided"]</metric>
    <enumeratedValueSet variable="political-scenario">
      <value value="&quot;Technocratic-India&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="social-threshold">
      <value value="0.2"/>
      <value value="0.3"/>
      <value value="0.4"/>
      <value value="0.5"/>
      <value value="0.6"/>
      <value value="0.7"/>
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="population-size">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="AdoptionRateSensitivity" repetitions="50" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>od-completed? and ticks &gt;= od-end-tick + 200</exitCondition>
    <metric>rate-enrollment</metric>
    <metric>rate-resistance</metric>
    <metric>rate-undecided</metric>
    <metric>opinion-polarization</metric>
    <metric>current-institutional-credibility</metric>
    <metric>time-to-stabilization</metric>
    <metric>cascade-size</metric>
    <metric>ses-breakdown-enrollment</metric>
    <metric>ses-breakdown-resistance</metric>
    <metric>ses-breakdown-undecided</metric>
    <metric>digital-divide-effect</metric>
    <metric>network-density</metric>
    <metric>od-duration</metric>
    <metric>ca-initiated?</metric>
    <metric>ca-duration</metric>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>count turtles with [action-state = "enrolled"]</metric>
    <metric>count turtles with [action-state = "resisted"]</metric>
    <metric>count turtles with [action-state = "undecided"]</metric>
    <enumeratedValueSet variable="adoption-rate">
      <value value="0.2"/>
      <value value="0.3"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="0.95"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="ShockRobustness" repetitions="100" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>od-completed? and ticks &gt;= od-end-tick + 200</exitCondition>
    <metric>rate-enrollment</metric>
    <metric>rate-resistance</metric>
    <metric>rate-undecided</metric>
    <metric>opinion-polarization</metric>
    <metric>current-institutional-credibility</metric>
    <metric>time-to-stabilization</metric>
    <metric>cascade-size</metric>
    <metric>ses-breakdown-enrollment</metric>
    <metric>ses-breakdown-resistance</metric>
    <metric>ses-breakdown-undecided</metric>
    <metric>digital-divide-effect</metric>
    <metric>network-density</metric>
    <metric>od-duration</metric>
    <metric>ca-initiated?</metric>
    <metric>ca-duration</metric>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>count turtles with [action-state = "enrolled"]</metric>
    <metric>count turtles with [action-state = "resisted"]</metric>
    <metric>count turtles with [action-state = "undecided"]</metric>
    <enumeratedValueSet variable="seed">
      <value value="123"/>
      <value value="456"/>
      <value value="789"/>
      <value value="101112"/>
      <value value="131415"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
