extensions [nw]

globals [
  ; Population tracking
  total-enrolled
  total-resisted
  total-undecided

  ; Cascade detection
  cascade-size-this-tick

  ; Institutional response
  institutional-credibility
]

turtles-own [
  ; Core opinion (aggregate of trust, surveillance concern, inclusion benefit)
  opinion-score           ; 0-1, higher = more favorable to system

  ; Demographics for clustering
  socioeconomic-status    ; "low", "medium", "high" - affects initial opinions and network
  memory-of-exclusion     ; 0-1, accumulated negative experiences

  ; Action state
  action-state           ; "undecided", "enrolled", "resisted"

  ; Social influence
  peer-influence         ; current social proof from neighbors
]

to setup
  clear-all
  reset-globals
  create-population
  setup-clustered-network
  seed-early-actors
  update-metrics
  reset-ticks
end

to reset-globals
  set total-enrolled 0
  set total-resisted 0
  set total-undecided 0
  set cascade-size-this-tick 0
  set institutional-credibility 1.0
end

to create-population
  create-turtles population-size [
    ; Assign socioeconomic status (creates natural clustering)
    let rand random-float 1.0
    set socioeconomic-status (
      ifelse-value
      rand < 0.4 ["low"]
      rand < 0.8 ["medium"]
      ["high"]
    )

    ; Memory of exclusion varies by SES (low SES more excluded historically)
    set memory-of-exclusion (
      ifelse-value
      socioeconomic-status = "low" [0.3 + random-normal 0 0.15]
      socioeconomic-status = "medium" [0.1 + random-normal 0 0.1]
      [0.05 + random-normal 0 0.08]
    )
    set memory-of-exclusion max list 0 min list 1 memory-of-exclusion

    ; Opinion score: higher SES more favorable, but moderated by memory
    let base-opinion (
      ifelse-value
      socioeconomic-status = "low" [0.3]
      socioeconomic-status = "medium" [0.5]
      [0.7]
    )
    set opinion-score base-opinion - (memory-of-exclusion * 0.4) + random-normal 0 opinion-variance
    set opinion-score max list 0 min list 1 opinion-score

    set action-state "undecided"
    set peer-influence 0

    setxy random-xcor random-ycor
  ]
end

to setup-clustered-network
  ; Create network with socioeconomic clustering
  ask turtles [
    ; Base random connections
    let num-random min list 3 (count other turtles)
    if num-random > 0 [
      create-links-with n-of num-random other turtles
    ]

    ; Additional clustering by SES
    let same-ses other turtles with [socioeconomic-status = [socioeconomic-status] of myself]
    let num-clustered round (count same-ses * ses-clustering * 0.05)
    if num-clustered > 0 and count same-ses > 0 [
      create-links-with n-of (min list num-clustered count same-ses) same-ses
    ]
  ]

  ; Ensure no isolates
  ask turtles with [count link-neighbors = 0] [
    if count other turtles > 0 [
      create-link-with one-of other turtles
    ]
  ]
end

to seed-early-actors
  ; Early adopters: highest opinion scores
  let num-adopters round (count turtles * 0.05)
  if num-adopters > 0 [
    ask max-n-of num-adopters turtles [opinion-score] [
      set action-state "enrolled"
    ]
  ]

  ; Early resisters: lowest opinion scores + high memory of exclusion
  let num-resisters round (count turtles * 0.03)
  if num-resisters > 0 [
    ask min-n-of num-resisters turtles with [action-state = "undecided"]
        [opinion-score - memory-of-exclusion] [
      set action-state "resisted"
    ]
  ]
end

to go
  set cascade-size-this-tick 0

  update-peer-influence
  update-actions
  update-network-ties
  update-institutional-response

  update-metrics
  color-agents
  tick
end

to update-peer-influence
  ask turtles [
    let myneighbors link-neighbors
    if count myneighbors > 0 [
      let enrolled-neighbors count myneighbors with [action-state = "enrolled"]
      let resisted-neighbors count myneighbors with [action-state = "resisted"]
      let total-neighbors count myneighbors

      ; Peer influence is difference between enrollment and resistance pressure
      set peer-influence (enrolled-neighbors - resisted-neighbors) / total-neighbors
    ]
  ]
end

to update-actions
  ask turtles with [action-state = "undecided"] [
    ; Combined influence: personal opinion + peer pressure + policy pressure
    let total-influence opinion-score + (peer-influence * 0.5) + (policy-type * 0.3 * institutional-credibility)

    ; Resistance influence: memory of exclusion + negative peer influence + policy backlash
    let resistance-influence memory-of-exclusion - (peer-influence * 0.5) + (policy-type * 0.4)

    ; Decision thresholds
    if total-influence > (1 - social-threshold) [
      set action-state "enrolled"
      set cascade-size-this-tick cascade-size-this-tick + 1
    ]

    if resistance-influence > (1 - social-threshold) [
      set action-state "resisted"
      set cascade-size-this-tick cascade-size-this-tick + 1
    ]
  ]

  ; Cascade reinforcement
  if cascade-size-this-tick >= 5 [
    ask turtles with [action-state != "undecided"] [
      ; Reinforce recent switchers
      if action-state = "enrolled" [
        set opinion-score min list 1 (opinion-score + 0.05)
      ]
    ]
  ]
end

to update-network-ties
  ; Dynamic rewiring: break ties with those who chose differently
  ask links [
    let agent1 end1
    let agent2 end2

    ; Higher probability of breaking ties if different actions AND different SES
    if [action-state] of agent1 != "undecided" and
       [action-state] of agent2 != "undecided" and
       [action-state] of agent1 != [action-state] of agent2 [

      let break-probability 0.1
      if [socioeconomic-status] of agent1 != [socioeconomic-status] of agent2 [
        set break-probability 0.2
      ]

      if random-float 1.0 < break-probability [
        die
      ]
    ]
  ]

  ; Form new ties with similar others (every 5 ticks to avoid computational overhead)
  if ticks mod 5 = 0 [
    ask turtles with [action-state != "undecided" and count link-neighbors < 12] [
      let similar-agents other turtles with [
        action-state = [action-state] of myself and
        distance myself < 15
      ]
      if count similar-agents > 0 [
        let new-partner one-of similar-agents with [count link-neighbors < 12]
        if new-partner != nobody and not link-neighbor? new-partner [
          create-link-with new-partner
        ]
      ]
    ]
  ]
end

to update-institutional-response
  let resistance-rate total-resisted / count turtles

  ; Only update if we have agents (avoid division by zero)
  if count turtles > 0 [
    ; Institutional credibility drops if resistance too high
    if resistance-rate > inst-response-threshold [
      set institutional-credibility max list 0.3 (institutional-credibility - 0.05)
    ]

    ; Gradual recovery when resistance is low
    if resistance-rate < (inst-response-threshold * 0.7) [
      set institutional-credibility min list 1.0 (institutional-credibility + 0.01)
    ]
  ]
end

to update-metrics
  set total-enrolled count turtles with [action-state = "enrolled"]
  set total-resisted count turtles with [action-state = "resisted"]
  set total-undecided count turtles with [action-state = "undecided"]
end

to color-agents
  ask turtles [
    if action-state = "enrolled" [ set color green ]
    if action-state = "resisted" [ set color red ]
    if action-state = "undecided" [
      ; Color undecided by SES for clustering visualization
      if socioeconomic-status = "low" [ set color gray - 2 ]
      if socioeconomic-status = "medium" [ set color gray ]
      if socioeconomic-status = "high" [ set color gray + 2 ]
    ]

    ; Highlight cascade participants
    if cascade-size-this-tick >= 5 [ set size 1.3 ]
    if cascade-size-this-tick < 5 [ set size 1.0 ]
  ]
end

; Reporters
to-report enrollment-rate
  report total-enrolled / count turtles
end

to-report compute-resistance-rate
  report total-resisted / count turtles
end

to-report cascade-size
  report cascade-size-this-tick
end

to-report average-opinion
  report mean [opinion-score] of turtles
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
1
1
1
ticks
30.0

BUTTON
5
5
68
38
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
76
5
139
38
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

SLIDER
3
41
175
74
population-size
population-size
0
1000
950.0
100
1
NIL
HORIZONTAL

SLIDER
4
82
176
115
policy-type
policy-type
0
1
1.0
0.5
1
NIL
HORIZONTAL

SLIDER
5
122
177
155
opinion-variance
opinion-variance
0.1
0.4
0.1
0.1
1
NIL
HORIZONTAL

SLIDER
5
162
177
195
ses-clustering
ses-clustering
0.2
0.8
0.3
0.1
1
NIL
HORIZONTAL

SLIDER
5
203
177
236
social-threshold
social-threshold
0.1
0.5
0.5
0.1
1
NIL
HORIZONTAL

SLIDER
5
244
194
277
inst-response-threshold
inst-response-threshold
0.15
0.9
0.9
0.05
1
NIL
HORIZONTAL

PLOT
211
456
411
606
Behaviour
ticks
population proportion
0.0
100.0
0.0
1.0
true
false
"" ""
PENS
"enrolled" 1.0 0 -13345367 true "" "plot (total-enrolled / count turtles)"
"resisted" 1.0 0 -13840069 true "" "plot (total-resisted / count turtles)"
"undecided" 1.0 0 -2674135 true "" "plot (total-undecided / count turtles)"

PLOT
419
456
619
606
Institutional Credibility
ticks
credibility (0-1)
0.0
10.0
0.0
1.0
true
false
"" "set-current-plot \"Institutional Credibility\"\nplot institutional-credibility"
PENS
"default" 1.0 0 -7713188 true "" "plot institutional-credibility"

PLOT
627
456
827
606
Size of Cascade
ticks
cascade size
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"cascade-size" 1.0 0 -8630108 true "" "plot cascade-size"

PLOT
835
456
1035
606
Distribution of Opinion
ticks
opinion score(0-1)
0.0
10.0
0.0
1.0
true
false
"" ";histogram [opinion-score] of turtles"
PENS
"Overall" 1.0 0 -16777216 true "" "plot average-opinion"
"Low SES" 1.0 0 -13791810 true "" "plot mean [opinion-score] of turtles with [socioeconomic-status = \"low\"]"
"Med SES" 1.0 0 -6917194 true "" "plot mean [opinion-score] of turtles with [socioeconomic-status = \"medium\"]"
"High SES" 1.0 0 -955883 true "" "plot mean [opinion-score] of turtles with [socioeconomic-status = \"high\"]"

PLOT
211
615
411
765
Network Connectivity
ticks
count
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"Total Links" 1.0 0 -16777216 true "" "plot count links"
"Average Networks" 1.0 0 -955883 true "" "plot mean [count link-neighbors] of turtles"

PLOT
419
615
619
765
Socioeconomic Distribution
time
percentage
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot (count turtles with [socioeconomic-status = \"low\" and action-state = \"enrolled\"]) / (count turtles with [socioeconomic-status = \"low\"]) * 100"

PLOT
629
614
829
764
Adoption Rates
ticks
rate (01)
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"enrollment-rate" 1.0 0 -955883 true "" "plot enrollment-rate"
"resistance-rate" 1.0 0 -14835848 true "" "plot compute-resistance-rate"

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
  <experiment name="GeneralCA" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>ticks = 200</exitCondition>
    <metric>enrollment-rate</metric>
    <metric>compute-resistance-rate</metric>
    <metric>avg-opinion</metric>
    <metric>cascade-size</metric>
    <metric>institutional-credibility</metric>
    <enumeratedValueSet variable="policy-type">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="opinion-variance">
      <value value="0.1"/>
      <value value="0.2"/>
      <value value="0.3"/>
      <value value="0.4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="social-threshold">
      <value value="0.1"/>
      <value value="0.2"/>
      <value value="0.3"/>
      <value value="0.4"/>
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="inst-response-threshold">
      <value value="0.15"/>
      <value value="0.45"/>
      <value value="0.7"/>
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ses-clustering">
      <value value="0.2"/>
      <value value="0.4"/>
      <value value="0.6"/>
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="population-size">
      <value value="300"/>
      <value value="500"/>
      <value value="700"/>
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="MandatoryScenario" repetitions="5" runMetricsEveryStep="true">
    <setup>set policy-type 1.0
setup</setup>
    <go>go</go>
    <exitCondition>ticks = 100</exitCondition>
    <metric>enrollment-rate</metric>
    <metric>compute-resistance-rate</metric>
    <metric>average-opinion</metric>
    <metric>cascade-size</metric>
    <enumeratedValueSet variable="policy-type">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="opinion-variance">
      <value value="0.1"/>
      <value value="0.2"/>
      <value value="0.3"/>
      <value value="0.4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="social-threshold">
      <value value="0.1"/>
      <value value="0.2"/>
      <value value="0.3"/>
      <value value="0.4"/>
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="inst-response-threshold">
      <value value="0.15"/>
      <value value="0.3"/>
      <value value="0.5"/>
      <value value="0.7"/>
      <value value="0.9"/>
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
