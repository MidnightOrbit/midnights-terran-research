# Military-Industrial Complex (MIC): design and prototype roadmap

Status (2026-11-28): **M0a proven in-game** (loaded, triggered, 20 managed factions, 14 eligible, contracts
#1–#4 generated with correct arithmetic, no script errors). **M0b written and validated offline, not yet run
in-game** (see §8). In-game snapshot of M0a: `.claude/backups/known-good-mic-m0a-ingame/`.
Game target: X4 9.00 (`version.dat` = 900) with all 7 Egosoft DLCs. No third-party mods installed.

Evidence tiers follow the project rules: READ = I read the vanilla file and line cited, INFERRED =
my reading but not engine-proven, ASSUMED = not checked yet.

---

## 1. Architecture

```
               ┌─────────────────── MD backend (works with no UI) ───────────────────┐
 universe ──▶  │ Demand scanner ─▶ Contract generator ─▶ Contract store              │
 (stations,    │   shortages         budgets, caps,       player.entity.$MIC_State   │
  fleets,      │   losses            dedupe, expiry       (persists, Lua-readable)   │
  relations)   │   wars                    │                     ▲                   │
               │                           ▼                     │                   │
               │ Fulfilment trackers (trade events, fleet transfer, build) ──┐       │
               │ Standing & diplomacy (points, ranks, objector penalties,    │       │
               │   warnings, sanctions, exclusivity)  ◀──────────────────────┘       │
               └──────────────────────────────▲─────────────────────────────────────┘
                                              │ raise_lua_event / AddUITriggeredEvent
               ┌──────────────────────────────┴─────────────────────────────────────┐
               │ Lua UI (M1+): Corporate Procurement menu, context-menu "assign"     │
               │ actions, settings. Reads state, sends commands; owns no logic.      │
               └────────────────────────────────────────────────────────────────────┘
```

Rules the structure follows (spec §20):
- **All logic is in MD.** The UI only reads `player.entity.$MIC_State` and sends commands. With the
  UI closed or missing, contracts keep generating, expiring and completing.
- **No hardcoded faction list.** Eligible factions = `global.$FactionManagers` keys (READ:
  `md/factionlogic.xml:367-370`, every faction with a faction-logic manager registers there), minus
  a configurable exclusion list, minus inactive factions. DLC, plot and mod factions appear
  automatically. Per-faction tuning (reputation tiers, doctrine) is a table row with a `$default`
  fallback.
- **Keys are faction-ID strings** (`'$' + $faction.id`), the vanilla idiom (READ:
  `md/notifications.xml:3974`), so the Lua side can read them.
- **Real relations, never hardcoded rivalries.** Objectors come from `get_factions_by_relation
  relation="enemy"` at generation time (READ: `md/factionlogic.xml:1561`) and will be re-evaluated
  at acceptance and delivery (M2).

## 2. Engine mechanisms to reuse (copy, do not compose)

| Need | Vanilla mechanism | Evidence |
|---|---|---|
| Resource shortage signal | `$station.resources.pure.list` × `cargo.{w}.count / cargo.{w}.target` | READ `md/rml_supplyfactory.xml:89,267` |
| Military strength | fight-ship count weighted S5/M8/L35/XL75 | READ `md/factionlogic.xml:1019-1038` (commented-out vanilla code) |
| Count resource deliveries | `event_trade_completed buyer=$station`, `event.param.seller.owner`, `.transferredamount` | READ `md/rml_deliver_wares.xml:82-96` |
| **No double payment** | Player sells at the normal price, so the wares really enter the station's stock; the contract pays only a **premium** on top | design choice, follows from the row above |
| Ship procurement + ownership transfer | `md.GM_GetExactFleet.Start` with `WithoutOffer`, `MissionCue`, `ReportSignalCue`; fleet spec `[table[$macro or $shiptype, $amount, $equipment]]` | READ `md/gm_getexactfleet.xml:280-330`, caller `md/x4ep1_war_subscriptions.xml:11180` |
| Transfer bookkeeping | `md.LIB_Generic.TransferShipOwnership` | READ `md/lib_generic.xml:1551` |
| Reputation in UI units | `$f.relation.{$f.relationto.{faction.player}}.uivalue` (−30..+30) | READ `libraries/scriptproperties.xml:1841` |
| Station construction contracts | `md.GM_BuildStation.Start` | READ caller `md/x4ep1_war_subscriptions.xml:11864`; params not read yet |
| Contract-issuer actor | `md.$FactionData.{f}.$Representative`, `$f.headquarters` | READ `md/factionlogic.xml:652,764`, `scriptproperties.xml:1877` |
| Government "subscription" model | Venture/war subscriptions already run faction-specific mission threads | READ `md/x4ep1_war_subscriptions.xml` (17k lines, studied only in part) |

⚠ **Known weak link: delivered ships doing real work (spec §9, §18).** Vanilla `rml_deliver_fleet`
gives the largest delivered ship a `Patrol` order and makes the rest its defence wing (READ
`md/rml_deliver_fleet.xml:829-851`, with an Egosoft `TODO: Set commandeerable for FactionLogic`).
That is exactly the "idle extra fleet" the spec rejects. Faction-logic goals recruit ships with
`find_ship_by_true_owner ... jobtags="[tag.military, tag.factionlogic]" commandeerable="true"`
(READ `md/factionsubgoal_recon.xml:270`, `factiongoal_patrolcoordinationservice.xml:300`). A
delivered ship has no job, so I **think** faction logic never recruits it (INFERRED, unverified).
Research for M0c: is there an action that gives a ship a job or makes it commandeerable? If not,
the fallback is MIC-side orders: `Patrol` in the faction's most threatened contested sector,
re-targeted every scan.

## 3. Milestones

Each milestone ends with one in-game test whose pass or fail decides the next step.

| # | Deliverable | Spec § | Depends on |
|---|---|---|---|
| **M0a** | Backend: faction registry, per-faction state, demand scanner, contract generation, budgets/caps/expiry, logbook output | 1, 2, 3, 4, 20 | none |
| M0b | Accept/decline flow (temporary vanilla mission offers, or a debug conversation), resource contracts tracked via `event_trade_completed`, premium payment, procurement points, rank-ups, notifications | 5, 10, 17 | M0a proven |
| M0c | Fleet replenishment contracts via `GM_GetExactFleet`; ships put to work after transfer | 9, 18 | M0b, research above |
| M1 | Corporate Procurement UI (Overview, Contracts, Faction Relations) on the chosen UI dependency; MD↔Lua bridge with timeouts | 15, 19 | dependency decision |
| M2 | Diplomacy: objector penalties scaled by relation × war × asset class × value, warnings → suspension → blacklist, reconciliation, preview before accepting | 6, 7 | M0c |
| M3 | Supply agreements (recurring quotas, assigned stations and fleets, renewals) + context-menu asset assignment | 11, 16 | M1 |
| M4 | Exclusivity agreements, government funding with obligations and clawback | 8, 12 | M2 |
| M5 | Infrastructure contracts (`GM_BuildStation`), strategic programmes (multi-stage; Project Leviathan / Aegis / Hephaestus / Crusader and equivalents), Finances/History/Settings tabs | 13, 14, 15 | M3, M4 |

## 4. M0a: what was built

`md/mic_core.xml` (one new, uniquely named mdscript, so no vanilla path collision):

- `OnSetupStart`: fires on `md.Setup.Start` (new game and every save load, READ `md/setup.xml:22-40`).
  Writes a `[MIC]` line to debug.txt, a notification, and a logbook entry: the load and trigger markers.
- `EnsureState`: creates every missing key, so later versions add settings without patch blocks.
- `Tick` (every 60 s, instantiated `checkinterval` like `md/factionlogic.xml:691`): expires stale
  offers, then scans **one** faction (round robin), spreading the cost.
- `ScanFaction`: shortages, strength snapshot, enemies, budget regeneration; generates at most one
  replenishment contract and one resource contract per scan, up to 3 open offers per faction.
- Every new contract is written to the logbook (General) and debug.txt as
  `[MIC] NEW #id Faction [category]: what. Pay. Needs rep +N (you: M), rank R. Objectors: ...`

Default settings (all in `$MIC_State.$Settings`, configurable later from the UI):

| Setting | Default | Meaning |
|---|---|---|
| TickSeconds | 60 | one faction scanned per tick (the cue interval is still a fixed 60s) |
| MaxAvailablePerFaction | 3 | open offers per faction |
| OfferLifetime | 2 h | unaccepted offers expire and refund their reservation |
| ShortagePercent | 25 | a pure resource below this % of its storage target counts as short |
| ResourcePremiumPercent | 25 | premium over the average ware price, paid on top of the normal sale |
| ResourceMaxUnits | 20,000 | cap per resource contract |
| LossThresholdPercent | 5 | strength drop between two scans that triggers replenishment |
| BudgetCap / BudgetRegenPerScan | 25M / 2M Cr | per-faction procurement budget |
| RepTiers | default `[5,10,15,20,25,30]`; Terran +3, Teladi/Ministry −2 | UI reputation per tier 1–6 (spec §4) |
| RankPoints | `[0,100,400,1200,3000,8000]` | ranks 1–6 (spec §5) |

### Known approximations in M0a (fix before M0c)

- **Losses come from a strength delta between scans, not from kill events.** A faction moving ships
  out of a job, or building fast, hides losses; it is a coarse signal (INFERRED). Better source to
  research: `event_object_destroyed` filtered to fight-purpose ships of eligible factions, kept as a
  rolling window. That needs a cost measurement first.
- The first scan of each faction has no previous snapshot, so the first replenishment contract can
  appear only on the second pass (about 15 min with ~15 factions).
- Shortages are summed over all of a faction's stations, so a contract's destination is the single
  worst station while the amount reflects the whole faction. M0b will split deliveries across
  stations, or cap the amount to the destination's own shortfall.
- Replenishment payment is not computed yet; the plan is the vanilla fleet value × multiplier.

## 5. M0a in-game test

**Acceptance criteria (each one observable):**
1. *Loaded:* debug.txt has `[MIC] MIC_Core loaded`. Missing = the mod did not load; stop there.
2. *Triggered:* the notification "Procurement backend online" and a logbook entry appear on load.
3. *Scanning:* within about 2 min, `[MIC] scan queue rebuilt: N factions` (expect about 10–20) and
   `[MIC] scan <faction>: ...` lines with non-zero `stations=` and `strength=` for major factions.
4. *Generating:* within about 15 min, at least one `[MIC] NEW #...` resource contract with a real
   ware, station and sector name, and a premium in the thousands to millions of credits.
5. *No errors:* `x4debug triage` shows no `mic_core.xml` errors (property lookup failures, bad
   expressions).

**Live tracking.** Every line starts with `[MIC][TAG]`. `$Settings.$DebugLevel`: 0 = `[WARN]` only,
1 = info, 2 = verbose (the prototype default). Tags:

| Tag | Level | What it shows |
|---|---|---|
| `[LOAD]` `[STATE]` | 0 / 1 / 2 | load marker; state dump on every load (counters, then each open contract at level 2) |
| `[QUEUE]` | 1 / 2 | eligible factions per cycle; at level 2, each excluded or inactive faction with its reason |
| `[TICK]` | 2 | heartbeat every 60 s: queue length, open contracts, cycle number |
| `[SCAN]` | 1 / 2 | per-faction summary; player reputation (UI and raw) and budget change |
| `[SHORT]` `[MIL]` `[WAR]` | 2 | every short ware with its worst station; fleet counts vs the previous scan; enemy list |
| `[GEN-RES]` `[GEN-REP]` | 1 / 2 | every generation decision with its reason, including "no contract because …" and the payment arithmetic |
| `[NEW]` `[EXPIRE]` | 1 / 2 | contract created (and budget left), contract expired and refunded |
| `[CYCLE]` | 1 | one summary per full pass, **also written to the logbook** so it is readable in play |
| `[WARN]` | always | unexpected state: missing faction registry, empty queue, eligible faction with 0 stations, premium ≤ 0, a cycle with 0 contracts |

Read with `x4debug triage`, or `grep '\[MIC\]' debug.txt` for the trace.

**Assumption chain, with a confidence for each link:**

| Link | Confidence | If it fails |
|---|---|---|
| The engine loads a new mdscript from `extensions/mic/md/` | 97% (standard) | read the `content.xml` / folder error |
| `md.Setup.Start` fires the instantiated start cue on load | 92% (READ, the comment in `setup.xml` says so) | add an `event_game_loaded` cue |
| `global.$FactionManagers` is populated by the time the first Tick runs | 85% | the Tick retries every 60 s, so it self-heals; log shows count 0 |
| The `$f.relation.{x}.uivalue` expression evaluates | 85% | fall back to `relation.<range>` checks |
| A `checkinterval` + `instantiate` cue with a condition ticks | 90% | drop the condition, guard in the actions |
| Table literals `table[$s = 0, ...]` with `{'$'+id}` access behave as one key space | 85% | log shows a missing lookup; switch to `.$s` access |
| Money/integer arithmetic and the `(x)i` cast for points | 80% | a property-lookup or type error line names the expression |
| Generated values are plausible | 70%: ShortagePercent and budgets are guesses | tune the settings; a test that changes only numbers |

**Test profile:** a throwaway save. `save="0"` means the save does not depend on the mod, but
`player.entity.$MIC_State` is still written into it (residue).

## 6. Decisions the user owns

1. **UI dependency for M1.** Candidates from the spec: kuertee's UI Extensions (UIX), SirNukes Mod
   Support APIs, Chem O'Dun's Context Menu API, Options Helper. None is installed. Their 9.00
   compatibility and current versions are **unverified**: Nexus API research before choosing.
2. **Acceptance flow in M0b** (before the custom UI exists): temporary vanilla mission offers
   (reuses the Mission Manager now, removed later) or a minimal debug conversation.
3. **Ownership of delivered infrastructure (M5):** transfer to the faction, or a subsidy with player
   ownership. The spec allows both; per-contract is possible.

## 7. Open research (ranked by how much it blocks)

1. Whether delivered ships can join faction-logic jobs or goals (blocks §9 and §18 done properly).
2. `GM_GetExactFleet` text page layout: own t-file page with offsets +1..+12 (READ `gm_getexactfleet.xml:57-114`).
3. Cost of a galaxy-wide `event_object_destroyed` listener versus snapshot deltas.
4. Whether `event_trade_completed` accepts a group or list of buyers, so one cue can track many destinations.
5. Nexus API: UIX, SirNukes APIs, Context Menu API and Options Helper for 9.00.

## 8. M0b (2026-11-28): visibility, vanilla offers, top-level menu

User decisions this session: contracts are shown or logged **only** when the player meets their requirements;
eligible contracts appear in the **vanilla Mission Offers list** when the player is near their destination
(this settles §6 decision 2); MIC gets its **own top-bar tab and icon** listing contracts galaxy-wide, sectioned
by faction, sorted by payout or by type.

| Change | How | Evidence |
|---|---|---|
| Objector "mismatch" | Not a count bug: objectors were only ever meant for military contracts (§1). The scan line now says `military-objectors=`; supply contracts say `n/a (supply contracts provoke no objections)` | M0a log: scan `objectors: 6`, contract `Objectors: none` |
| Visibility gate | `CheckEligible` (rep ≥ `$minrep`, rank ≥ `$minrank`); logbook only when eligible; `AnnouncePending` announces later if reputation rises. debug.txt still traces every contract, tagged `[HIDDEN]` | rep expression already proven in M0a |
| Vanilla offers | `SpawnOffer` starts `md.GM_LargeSupply.Start` (params copied from its own `GenerateGenericMission_Variant_1_Ref`; report cue copied from `x4ep1_war_subscriptions.xml` `MM__Standard_GM_Event`). `RewardCr` = MIC premium, `GenerateReward=false`. Player sells wares normally (`rml_largesupply.xml:123` counts `event_player_trade_completed`); mission pays the premium on success (`gm_largesupply.xml:721`) | READ |
| Contract states | available → active (offer accepted) → completed (points, rank) or back to available (failed/aborted). Expiry withdraws a live offer via `CancelOfferCue` | |
| UI data | `player.entity.$MIC_UI`: plain strings/numbers, republished every tick and on menu open (`event_ui_triggered screen='MICMenu'`), then `raise_lua_event 'MIC.UIUpdated'` | SN userdata API uses the same blackboard round trip |
| Menu | `ui.xml` + `ui/mic_menu.lua`, modelled on `menu_help.lua`; tab appended to `Helper.topLevelMenus` after Help | `helper.lua:9772` |
| Icon | `mic_tlt`: 128×128 DXT5 DDS, gzipped, same form as vanilla `tlt_help` and DLC icons | measured: identical 22,000-byte layout |
| Text | `t/0001-l044.xml` page 1773100, laid out like vanilla page 30141 | |

**Needs Protected UI Mode OFF** for the menu (unsigned Lua). The backend and vanilla offers work without it.

### M0b in-game test (acceptance criteria)

1. *Loaded:* `[MIC][UI] menu registered` and `[MIC][UI] top-level tab added` in debug.txt; `[MIC][LOAD] ... M0b`.
2. *Tab:* the shield-and-gear icon appears on the top bar after Help and opens the MIC menu without a Lua error.
3. *Gate:* with reputation 0 everywhere, no new `[MIC] ... procurement notice` logbook entries; debug.txt shows
   `-> [HIDDEN]`; the menu says "No procurement contracts are open to you" plus the hidden count.
4. *Offer:* with a faction at rep ≥ +10 and the player in a destination sector: `[MIC][OFFER] #N ... creating a
   vanilla mission offer`, then the offer appears in Mission Offers named "Procurement Contract".
5. *Accept/complete:* accepting logs `event: $MISSION_ACCEPTED` and the menu shows "(accepted)"; delivering logs
   `[MIC][DONE]` and pays the premium once.

Weakest links: the menu (first Lua; 75%), `GM_LargeSupply` accepting an external caller with our own text page
(80%), `($payment / 1Cr)i` producing a number in Lua (80%; only sorting depends on it).
Open from the M0a run: Kha'ak materials (khaakalloy, rawkhaakscrap) were picked for 2 of the first 4 contracts;
they may be impossible for the player to supply. Antigone counted 99 stations (unverified whether that includes
defence platforms or build sites).

**Decision (user, 2026-11-28): vanilla offers stay same-sector.** A MIC offer appears in Mission Offers only while the
player is in the contract's destination sector (the vanilla rule for these offers), so the vanilla list stays short.
The MIC tab is the galaxy-wide view.
