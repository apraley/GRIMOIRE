# Friction audit: simulated 60-shot commercial day

`tests/sim_commercial.lua` loads the *FIRST LIGHT :30* demo: a 60-shot, 8-scene,
20-setup, two-camera coffee commercial with a drone unit. It then shoots the
whole day **through button presses only**. The day includes:

- a 06:00 call
- relights (7 min) and company moves (22 min)
- 1–3 min take cycles, with take counts driven by priority and shot type
- ratings with a realistic mix; 12% of takes are TECH, and each gets an issue
  picked on the crank
- circled keepers
- continuity notes on four shots
- random pickups through the system menu
- lunch
- **a simulated crash (power pulled) mid-morning**
- **"losing the light" at 18:30** (RUSH mode), with C shots cut after 19:10
- the wrap report, and a relaunch afterwards

The run fails if any hard requirement breaks: NEXT in more than 2
interactions, lost takes, a lost report, or wrong resume state.

Screenshots of every screen were rendered from the recorded display lists
(`tools/render_frames.py`) and reviewed after each change. The first pass
found the problems below. Each one was fixed and re-measured.

## Findings and changes

| # | Friction found | Evidence | Change |
|---|---|---|---|
| 1 | **B undid GOT IT.** Undo was bound to B while an undo toast showed, and B is also "back". A reflexive back-press within 3 s silently reverted a GOT IT. This happened on its own in the screenshot tour. | tour frame showed `UNDONE: 01A-01 GOT IT` after pressing B to leave the slate | Undo removed from B. The hub opens with **UNDO pre-selected** for a few seconds after any undoable action, so undo is still **UP, A** (2 presses) and can't be triggered by accident. A regression test checks B after GOT IT opens details and changes nothing. |
| 2 | **The continuity card swallowed a take.** Flagged notes appeared as a modal card when LIVE entered a scene. The next A dismissed the card instead of logging the take, and the operator would believe it was logged. | sim assertion `rating overlay after A, got LiveScreen` | The card is now **non-modal**. It shows in LIVE's side panel for 9 s and never takes input. The header keeps a flag icon while notes are open. |
| 3 | **NEXT sent the crew away from a lit setup.** Strict priority ranking left B and C shots behind in the current setup to chase an A shot elsewhere, and every return cost a relight. | same seed: wrap **20:18**, 55 GOT IT, 5 CUT | Default ranking is now **BALANCED**: the current setup ranks three tiers higher, so it is finished first, then priority takes over. **RUSH** (system menu → GO → RUSH) keeps strict priority for "we're losing the light". Result: wrap **19:19** (−59 min), 58 GOT IT, 2 CUT, 22 setup visits for 20 setups. |
| 4 | **NEXT pressed twice from different screens gave the #2 candidate.** Hold-B within 8 s "cycles alternatives", which is right on LIVE (you just rejected the suggestion) but surprising from the builder or slate. | 5 failures in the "NEXT from anywhere" check | Cycling now applies only while LIVE is showing the NEXT banner. Everywhere else, NEXT always gives the #1 candidate. |
| 5 | **The remaining-time estimate was far too optimistic early in the day** (medians, one blended setup cost, no lunch). | 07:57 prediction **−266 min**, 10:05 **−164 min** | Uses means (setup costs are skewed), learns relight and company-move costs separately (with defaults until a move is observed), and adds lunch when the day's crew notes say `LUNCH HH:MM`. Now: 07:57 **−73**, 09:49 −118, 11:47 −68, 14:20 −86, 16:55 **±0**, 19:19 +6. |
| 6 | Continuity note took 8 presses: details, scroll to row, open list, add, tag, type, back, back. | sim metric | "+ CONTINUITY NOTE" is now the **second row** in details and returns straight to LIVE after typing: **6 presses including the keyboard confirm** (B, ↓, A, crank, A, type). |
| 7 | The rating card was a spatial diamond with arrows overlapping the labels, and it sat over LIVE's two-row footer. | screenshot review | Replaced with a list of 4 big rows, each led by its **d-pad arrow at 2× scale** (the thumb needs the direction, not the word). Overlays now cover the host footer cleanly. |
| 8 | Toasts covered the slate and stale toasts sat on top of pickers. | screenshot review | The slate never shows toasts (it gets a 250 ms invert flash and a small `LOGGED T5` in its title strip instead). Opening any overlay clears the current toast. |
| 9 | Hub labels were truncated (`WRAP REP..`, `DATA / SA..`, `UNDO 01A-..`). | screenshot review | Short labels. The undo target is shown in the status pane while UNDO is selected. |
| 10 | The best take drew a circle through its own numeral. | screenshot review | A ring icon plus a rating icon next to a 5× numeral. |

## Measured result (seed 42, after the changes)

```
wrap 19:19   58 GOT IT   2 CUT (C-priority, after light loss)   198 takes
629 interactions for the day = 10.5 per shot (takes included)

log a take ................. 1 press (A)
rate it .................... 1 press (d-pad)       TECH + issue: 2.7
GOT IT + go to next shot ... 1 press (→) — auto-NEXT moved on 58/58 times
circle keeper .............. 1 hold (A)
continuity note ............ 6 (incl. typing confirm)
RUSH (losing the light) .... 3 (system menu, GO, RUSH)
wrap report save + export .. 6
max spent on one shot ...... 19 (a many-take insert shot)

NEXT from: hub, browser, builder, slate, status picker, rating card,
progress, wrap report, settings form, package form, enum picker ... 1 (hold B)
NEXT from the system menu ........................................ 2
```

Crash drill: the device was power-cut between takes 23 and 24. On relaunch,
2 journal ops were replayed, **0 takes were lost**, and the app resumed in
LIVE on the same shot.

## Known limits

- The simulation uses stand-in font metrics. Check long descriptions on the
  real Asheville font in the Simulator before a shoot. All truncation uses
  runtime metrics, so text shortens rather than overflows.
- The estimate can't foresee unplanned returns to a setup, or breaks not
  written in crew notes. It converges as the day provides history.
