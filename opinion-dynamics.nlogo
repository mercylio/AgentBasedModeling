extensions [nw]

globals [
  avg-trust
  avg-surveillance
  avg-inclusion
  avg-memory
  avg-connections

  std-trust
  std-surveillance
  std-inclusion
  trust-entropy
  surveillance-entropy
  inclusion-entropy

  links-formed-this-tick
  links-broken-this-tick
  total-links
  clustering-coefficient

  institutional-credibility
]

turtles-own [
  opinion-trust        ; 0-1
  opinion-surveillance ; 0-1
  opinion-inclusion    ; 0-1
  memory-score         ; 0-1, accumulated negative experiences
  vulnerability        ; 0-1, combines socioeconomic/digital literacy factors
  impressionability    ; 0-1, how easily influenced
]

to setup
  clear-all

  create-turtles 500 [
    setxy random-xcor random-ycor

    ;; Single vulnerability score (0=privileged, 1=highly vulnerable)
    set vulnerability random-float 1.0

    ;; Impressionability inversely related to vulnerability (vulnerable = more skeptical)
    set impressionability 0.4 - (vulnerability * 0.2)

    ;; Initial memory based on vulnerability so that vulnerable agents start with some negative experience
    ;set memory-score vulnerability * 0.3
    set memory-score vulnerability * 0.2 + random-float 0.1  ; smaller initial memory

    ;; Initialize opinions based on vulnerability and policy type
    let trust-noise (random-float 0.4 - 0.2)
    let surveillance-noise (random-float 0.4 - 0.2)
    let inclusion-noise (random-float 0.4 - 0.2)

    let base-trust 0.5 - (vulnerability * 0.3) + (policy-type * 0.15) + trust-noise
    let base-surveillance 0.4 + (vulnerability * 0.2) - (policy-type * 0.1) + surveillance-noise
    let base-inclusion 0.5 + (policy-type * 0.2) + inclusion-noise

    set opinion-trust bound-opinion base-trust
    set opinion-surveillance bound-opinion base-surveillance
    set opinion-inclusion bound-opinion base-inclusion

    ;; Initial institutional credibility score
    set institutional-credibility 1

  ]

  setup-network
  update-globals
  reset-ticks
end

to setup-network
  ;; Create small-world network based on vulnerability similarity
  ask turtles [
    let target-connections 2 + random 2  ; 2-4 connections per agent

    ;; Find similar agents (by vulnerability) to connect with
    let similar-agents other turtles with [
      abs (vulnerability - [vulnerability] of myself) < 0.4  ; similarity requirement
    ]

    ;; Connect to most similar available agents
    let available-partners similar-agents with [count link-neighbors < 4]
    if count available-partners >= target-connections [
      let chosen-partners n-of target-connections available-partners
      ask chosen-partners [
        if not link-neighbor? myself [
          create-link-with myself
        ]
      ]
    ]
  ]
end

to go
  ;; Reset link change counters
  set links-formed-this-tick 0
  set links-broken-this-tick 0

  ;; 1. Institutional broadcasts (stochastic)
  if random 100 < broadcast-frequency [
    apply-institutional-broadcast
  ]

  ;; 2. Negative shocks (failures, scandals, exclusions)
  if random 100 < shock-frequency [
    apply-negative-shock
  ]

  ;; 3. Peer influence
  ask turtles [
    if any? link-neighbors [
      let peer one-of link-neighbors
      update-opinion-from-peer peer

      ;; Observational learning: learn from peer's bad experiences
      if observational-learning? and [memory-score] of peer > memory-score [
        let memory-transfer ([memory-score] of peer - memory-score) * 0.1
        set memory-score min list 1 (memory-score + memory-transfer)
      ]
    ]
  ]

  ;; 4. Network evolution every few ticks (to reduce computation)
  if ticks mod 3 = 0 [
    update-network
  ]

  ;; 5. Memory decay over time
  ask turtles [
    set memory-score max list 0 (memory-score - memory-decay)
  ]

  update-globals
  update-colours
  tick
end

to apply-institutional-broadcast
  ask turtles [
    ;; Resistance based on memory and vulnerability
    let resistance memory-score + (vulnerability * 0.2)
    let receptiveness institutional-credibility * (1 - resistance) * impressionability * broadcast-strength

    ;; Apply signals
    if trust-signal != 0 [
      set opinion-trust bound-opinion (opinion-trust + receptiveness * trust-signal)
    ]
    if surveillance-signal != 0 [
      set opinion-surveillance bound-opinion (opinion-surveillance + receptiveness * surveillance-signal)
    ]
    if inclusion-signal != 0 [
      set opinion-inclusion bound-opinion (opinion-inclusion + receptiveness * inclusion-signal)
    ]
  ]
end

to apply-negative-shock
  ;; Simulate system failures, scandals, exclusions
  ask turtles [
    let shock-impact shock-severity * (1 - policy-type * 0.5)  ; worse under mandatory systems
    let vulnerability-multiplier 1 + vulnerability  ; vulnerable agents hit harder

    ;; Negative shock reduces trust, increases surveillance concern, decreases inclusion belief
    set opinion-trust bound-opinion (opinion-trust - shock-impact * vulnerability-multiplier * 0.7)
    set opinion-surveillance bound-opinion (opinion-surveillance + shock-impact * vulnerability-multiplier * 0.5)
    set opinion-inclusion bound-opinion (opinion-inclusion - shock-impact * vulnerability-multiplier * 0.3)

    ;; Increase memory
    set memory-score min list 1 (memory-score + shock-impact * vulnerability-multiplier * 0.5)
  ]
end

to update-opinion-from-peer [peer]
  let opinion-dist calculate-opinion-distance self peer

  ;; Bounded confidence: only update if within threshold
  if opinion-dist <= confidence-threshold [
    let similarity-weight (1 - opinion-dist) ^ 2  ; squared for stronger similarity effect
    let memory-resistance memory-score * 0.7  ; stronger memory resistance
    let influence-strength similarity-weight * impressionability * (1 - memory-resistance) * 0.02  ; reduced from 0.05

    ;; Update each dimension toward peer
    set opinion-trust bound-opinion (opinion-trust + influence-strength * ([opinion-trust] of peer - opinion-trust))
    set opinion-surveillance bound-opinion (opinion-surveillance + influence-strength * ([opinion-surveillance] of peer - opinion-surveillance))
    set opinion-inclusion bound-opinion (opinion-inclusion + influence-strength * ([opinion-inclusion] of peer - opinion-inclusion))
  ]
end

to update-network
  ;; Track broken links
  let initial-links count links

  ;; Break links with agents who are too different
  ask links [
    let opinion-dist calculate-opinion-distance end1 end2
    ;if opinion-dist > confidence-threshold * 1.5 [  ; higher threshold for breaking than forming
    if opinion-dist > confidence-threshold * 1.2 [  ; higher threshold for breaking than forming
      die
      set links-broken-this-tick links-broken-this-tick + 1
    ]
  ]

  ;; Form new links with similar agents (limited rate to prevent runaway clustering)
  ask turtles with [count link-neighbors < 6] [  ; max 6 connections
    let potential-partners other turtles with [
      not link-neighbor? myself and
      ;count link-neighbors < 6 and
      count link-neighbors < 4 and
      calculate-opinion-distance myself self <= confidence-threshold and
      abs (vulnerability - [vulnerability] of myself) < 0.3  ; demographic similarity still matters
    ]

    if any? potential-partners and random-float 1 < 0.1 [  ; 30% chance to form new link
      let new-partner one-of potential-partners
      create-link-with new-partner
      set links-formed-this-tick links-formed-this-tick + 1
    ]
  ]

  ;; Update link count
  set total-links count links
end

to update-colours
  ask turtles [
    let trust-val max list 0 (min list 1 opinion-trust)
    let surveillance-val max list 0 (min list 1 opinion-surveillance)
    let inclusion-val max list 0 (min list 1 opinion-inclusion)
    let memory-val max list 0 (min list 1 memory-score)
    let vulnerability-val max list 0 (min list 1 vulnerability)

    if colour-mode = "trust" [
      ; Map to range 12-18 (light red to darker red, avoiding black)
      set color 12 + trust-val * 6
    ]
    if colour-mode = "surveillance" [
      ; Map to range 22-28 (light orange to darker orange)
      set color 22 + surveillance-val * 6
    ]
    if colour-mode = "inclusion" [
      ; Map to range 52-58 (light green to darker green)
      set color 52 + inclusion-val * 6
    ]
    if colour-mode = "memory" [
      ; Map to range 2-8 (light gray to darker gray)
      set color 2 + memory-val * 6
    ]
    if colour-mode = "vulnerability" [
      ; Map to range 102-108 (light blue to darker blue)
      set color 102 + vulnerability-val * 6
    ]
  ]
end

;; HELPER FUNCTIONS

to-report calculate-opinion-distance [agent1 agent2]
  let trust-diff abs ([opinion-trust] of agent1 - [opinion-trust] of agent2)
  let surveillance-diff abs ([opinion-surveillance] of agent1 - [opinion-surveillance] of agent2)
  let inclusion-diff abs ([opinion-inclusion] of agent1 - [opinion-inclusion] of agent2)
  report sqrt (trust-diff ^ 2 + surveillance-diff ^ 2 + inclusion-diff ^ 2) / sqrt 3
end

to-report bound-opinion [value]
  report max list 0 (min list 1 value)
end

to update-globals
  set avg-trust mean [opinion-trust] of turtles
  set avg-surveillance mean [opinion-surveillance] of turtles
  set avg-inclusion mean [opinion-inclusion] of turtles
  set avg-memory mean [memory-score] of turtles
  set avg-connections mean [count link-neighbors] of turtles
  set total-links count links

  ;; Calculate standard deviations for polarization
  set std-trust standard-deviation [opinion-trust] of turtles
  set std-surveillance standard-deviation [opinion-surveillance] of turtles
  set std-inclusion standard-deviation [opinion-inclusion] of turtles

  ;; Calculate entropy for polarization (more sophisticated measure)
  set trust-entropy calculate-entropy [opinion-trust] of turtles
  set surveillance-entropy calculate-entropy [opinion-surveillance] of turtles
  set inclusion-entropy calculate-entropy [opinion-inclusion] of turtles

  ;; Calculate clustering coefficient
  set clustering-coefficient calculate-clustering

  ;; Calculate institutional credibility
  if avg-trust < 0.3 [
  set institutional-credibility max list 0 (institutional-credibility - 0.01)
  ]
  if avg-trust > 0.5 [
    set institutional-credibility min list 1 (institutional-credibility + 0.005)
  ]
end

to update-colours-old
  ask turtles [
    ; Add bounds checking to ensure values are between 0 and 1
    let trust-val max list 0 (min list 1 opinion-trust)
    let surveillance-val max list 0 (min list 1 opinion-surveillance)
    let inclusion-val max list 0 (min list 1 opinion-inclusion)
    let memory-val max list 0 (min list 1 memory-score)
    let vulnerability-val max list 0 (min list 1 vulnerability)

    if colour-mode = "trust" [
      set color scale-color red trust-val 0 1
    ]
    if colour-mode = "surveillance" [
      set color scale-color orange surveillance-val 0 1
    ]
    if colour-mode = "inclusion" [
      set color scale-color green inclusion-val 0 1
    ]
    if colour-mode = "memory" [
      set color scale-color gray memory-val 0 1
    ]
    if colour-mode = "vulnerability" [
      set color scale-color blue vulnerability-val 0 1
    ]
  ]
end

to-report calculate-entropy [opinion-list]
  ;; Calculate Shannon entropy by binning opinions into 10 bins
  let bins n-values 10 [0]
  foreach opinion-list [ op ->
    let bin-index floor (op * 9.99)  ; ensures we don't get index 10
    set bins replace-item bin-index bins (item bin-index bins + 1)
  ]

  let total-count length opinion-list
  let entropy 0
  foreach bins [ bin-count ->
    if bin-count > 0 [
      let probability bin-count / total-count
      set entropy entropy - (probability * log probability 2)
    ]
  ]
  report entropy
end

to-report calculate-clustering
  ;; Average clustering coefficient across all nodes
  let total-clustering 0
  let nodes-with-neighbors 0

  ask turtles with [count link-neighbors >= 2] [
    let my-neighbors link-neighbors
    let neighbor-count count my-neighbors
    let possible-edges neighbor-count * (neighbor-count - 1) / 2

    let actual-edges 0
    ask my-neighbors [
      ask my-neighbors with [who > [who] of myself] [
        if link-neighbor? myself [
          set actual-edges actual-edges + 1
        ]
      ]
    ]

    if possible-edges > 0 [
      set total-clustering total-clustering + (actual-edges / possible-edges)
      set nodes-with-neighbors nodes-with-neighbors + 1
    ]
  ]

  ifelse nodes-with-neighbors > 0 [
    report total-clustering / nodes-with-neighbors
  ] [
    report 0
  ]
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
4
2
67
35
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
72
2
135
35
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

SWITCH
4
38
191
71
observational-learning?
observational-learning?
1
1
-1000

SLIDER
5
73
177
106
policy-type
policy-type
0
1.0
0.0
0.5
1
NIL
HORIZONTAL

SLIDER
6
108
178
141
broadcast-frequency
broadcast-frequency
0
100
90.0
10
1
NIL
HORIZONTAL

SLIDER
6
144
178
177
broadcast-strength
broadcast-strength
0
0.5
0.45
0.1
1
NIL
HORIZONTAL

SLIDER
7
178
179
211
shock-frequency
shock-frequency
0
20
10.0
5
1
NIL
HORIZONTAL

SLIDER
4
214
176
247
shock-severity
shock-severity
0
1
0.2
0.1
1
NIL
HORIZONTAL

SLIDER
5
249
177
282
trust-signal
trust-signal
-3
3
0.3
1
1
NIL
HORIZONTAL

SLIDER
5
284
177
317
surveillance-signal
surveillance-signal
-3
3
-0.3
1
1
NIL
HORIZONTAL

SLIDER
3
319
175
352
inclusion-signal
inclusion-signal
-3
3
0.15
1
1
NIL
HORIZONTAL

SLIDER
5
356
177
389
confidence-threshold
confidence-threshold
0
1
0.2
0.1
1
NIL
HORIZONTAL

SLIDER
3
386
175
419
memory-decay
memory-decay
0
0.05
0.001
0.01
1
NIL
HORIZONTAL

CHOOSER
7
422
145
467
colour-mode
colour-mode
"trust" "surveillance" "inclusion" "memory" "vulnerability"
1

PLOT
4
473
204
623
Average Opinion
ticks
0-1
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"trust" 1.0 0 -10899396 true "" "plot avg-trust"
"surveillance" 1.0 0 -955883 true "" "plot avg-surveillance"
"inclusion" 1.0 0 -13791810 true "" "plot avg-inclusion"

PLOT
212
473
412
623
Networks
ticks
0-8
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"avg-connections" 1.0 0 -16777216 true "" "plot avg-connections"
"std-connections" 1.0 0 -7500403 true "" "plot avg-connections"

PLOT
420
473
620
623
Average Memory
ticks
0-1
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"memory" 1.0 0 -16777216 true "" "plot avg-memory"

PLOT
629
473
829
623
Polarisation
ticks
0-0.5
0.0
10.0
0.0
0.5
true
false
"" ""
PENS
"trust std" 1.0 0 -16777216 true "" "plot standard-deviation [opinion-trust] of turtles"
"inclusion std" 1.0 0 -1664597 true "" "plot standard-deviation [opinion-inclusion] of turtles"
"surveillance std" 1.0 0 -13791810 true "" "plot standard-deviation [opinion-surveillance] of turtles"

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
  <experiment name="General Analysis OD" repetitions="10" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>ticks &gt;= 200</exitCondition>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>avg-net-density</metric>
    <metric>links-formed-this-tick</metric>
    <metric>links-broken-this-tick</metric>
    <enumeratedValueSet variable="media-shock?">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="corruption-active?">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="opinion-drift?">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trust-gap-break">
      <value value="0.005"/>
      <value value="0.009"/>
      <value value="0.01"/>
      <value value="0.05"/>
      <value value="0.1"/>
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trust-gap-form">
      <value value="0.1"/>
      <value value="0.2"/>
      <value value="0.3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="opinion-similarity">
      <value value="0.2"/>
      <value value="0.3"/>
      <value value="0.4"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Baseline" repetitions="5" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>ticks = 300</exitCondition>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>avg-net-density</metric>
    <metric>links-formed-this-tick</metric>
    <metric>links-broken-this-tick</metric>
    <metric>count turtles with [opinion-trust &lt; 0.3]</metric>
    <metric>count turtles with [count link-neighbors = 0]</metric>
    <enumeratedValueSet variable="mem-increment">
      <value value="0.04"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="corruption?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trust-gap-break">
      <value value="0.009"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="corruption-cycle-trust">
      <value value="0.15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="opinion-drift?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="corruption-penalty">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="media-shock-trust">
      <value value="0.3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="corruption-active?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="opinion-similarity">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="media-shock?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trust-gap-form">
      <value value="0.4"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="MediaShocks" repetitions="5" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>ticks = 300</exitCondition>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>avg-net-density</metric>
    <metric>links-formed-this-tick</metric>
    <metric>links-broken-this-tick</metric>
    <metric>count turtles with [opinion-trust &lt; 0.3]</metric>
    <metric>count turtles with [count link-neighbors = 0]</metric>
    <enumeratedValueSet variable="media-shock?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="corruption-active?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="opinion-drift?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Corruption" repetitions="5" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>ticks = 300</exitCondition>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>avg-net-density</metric>
    <metric>links-formed-this-tick</metric>
    <metric>links-broken-this-tick</metric>
    <metric>count turtles with [opinion-trust &lt; 0.3]</metric>
    <metric>count turtles with [count link-neighbors = 0]</metric>
    <enumeratedValueSet variable="media-shock?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="corruption-active?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="opinion-drift?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="MediaShockANDCorruption" repetitions="5" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>ticks = 300</exitCondition>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>avg-net-density</metric>
    <metric>links-formed-this-tick</metric>
    <metric>links-broken-this-tick</metric>
    <metric>count turtles with [opinion-trust &lt; 0.3]</metric>
    <metric>count turtles with [count link-neighbors = 0]</metric>
    <enumeratedValueSet variable="media-shock?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="corruption-active?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="opinion-drift?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="OpinionThresholds" repetitions="5" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>ticks = 300</exitCondition>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>avg-net-density</metric>
    <metric>links-formed-this-tick</metric>
    <metric>links-broken-this-tick</metric>
    <metric>count turtles with [opinion-trust &lt; 0.3]</metric>
    <metric>count turtles with [count link-neighbors = 0]</metric>
    <enumeratedValueSet variable="opinion-similarity">
      <value value="0.2"/>
      <value value="0.3"/>
      <value value="0.4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="media-shock?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="corruption-active?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="opinion-drift?">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="TrustNetworkResilience" repetitions="5" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>ticks = 300</exitCondition>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>avg-net-density</metric>
    <metric>links-formed-this-tick</metric>
    <metric>links-broken-this-tick</metric>
    <metric>count turtles with [opinion-trust &lt; 0.3]</metric>
    <metric>count turtles with [count link-neighbors = 0]</metric>
    <enumeratedValueSet variable="trust-gap-break">
      <value value="0.005"/>
      <value value="0.01"/>
      <value value="0.05"/>
      <value value="0.1"/>
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trust-gap-form">
      <value value="0.1"/>
      <value value="0.2"/>
      <value value="0.4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="media-shock?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="corruption-active?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="TrustNetworkResilience (copy)" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>ticks = 100</exitCondition>
    <metric>avg-trust</metric>
    <metric>avg-surveillance</metric>
    <metric>avg-inclusion</metric>
    <metric>avg-net-density</metric>
    <metric>links-formed-this-tick</metric>
    <metric>links-broken-this-tick</metric>
    <metric>count turtles with [opinion-trust &lt; 0.3]</metric>
    <metric>count turtles with [count link-neighbors = 0]</metric>
    <enumeratedValueSet variable="trust-gap-break">
      <value value="0.005"/>
      <value value="0.01"/>
      <value value="0.1"/>
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trust-gap-form">
      <value value="0.1"/>
      <value value="0.2"/>
      <value value="0.4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="media-shock?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="corruption-active?">
      <value value="false"/>
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
