# Military-Industrial Complex (MIC) — prototype, in development

Factions post government procurement contracts based on what is really happening in your universe:
stations running short of resources, and fleets that lost ships. Contracts you qualify for appear in a
**Military-Industrial Complex** tab on the top menu bar (after Help), and supply contracts near you appear as
normal **mission offers**.

**Not released.** This is the development branch. Expect test settings to be on and things to change.

## Install (for testing)

1. Copy the `mic` folder into `X4 Foundations/extensions/` (the game folder, not your Documents profile).
   The folder must be named `mic`: the icon path depends on it.
2. In game: **Settings → Extensions → Protected UI Mode → Off**. The tab is unsigned Lua and needs this.
   Contracts and mission offers work without it.
3. Use a throwaway save. The mod is not marked as a save dependency (`save="0"`), but it does store its state in the save.

Game 9.00+. No DLC or other mod required.

## How it works

- Every minute MIC scans one faction (round robin): stations below 25% of a resource, fleet strength, enemies.
- It creates up to 3 open contracts per faction, paid from a per-faction budget. Supply contracts pay a
  **premium on top of** the normal sale price, so you are never paid twice for the same wares.
- A contract is shown (logbook, tab, mission offers) only if your reputation and contractor rank meet its
  requirements. Hidden contracts are still traced in `debug.txt`, tagged `[HIDDEN]`.
- Supply contracts become vanilla mission offers (the game's own "large supply" mission) **only while you are in
  the destination sector**, so the vanilla list stays short. The MIC tab is the galaxy-wide view.
- Completing a contract earns procurement points with that faction, which raise your contractor rank.

## Test settings (ON in this build)

Stored in the save under `player.entity.$MIC_State.$Settings`:

| Setting | Value | Effect |
|---|---|---|
| `$TestMode` | 1 | every contract's reputation requirement becomes `$TestMinRep` (rank requirements still apply) |
| `$TestMinRep` | 0 | so any non-hostile faction's supply contracts are visible on a fresh save |
| `$TestLocalFirst` | 1 | when you enter a sector, its owner is scanned on the next tick and prefers a short ware at a station in that sector |
| `$DebugLevel` | 2 | verbose `[MIC]` lines in `debug.txt` |

Start the game with `-debug all -logfile debug.txt` to get the log. Every MIC line starts with `[MIC][TAG]`.

## Test status (2026-11-28)

Verified in game:
- Loads; the tab and its icon appear after Help; the menu opens and lists contracts, grouped by faction.
- Contracts generate for 20 managed factions (14 eligible); payout arithmetic correct; state survives save/load.
- Visibility: contracts are logged `-> VISIBLE` and announced in the logbook when you qualify (Terran at reputation
  30 passed the real check, not just the test override).
- Objector fix: supply contracts say `n/a (supply contracts provoke no objections)`; scans report `military-objectors`.
- Test option: entering the Asteroid Belt scanned Terran immediately.

Not yet verified:
1. **Vanilla mission offer.** Go to a contract's destination sector (e.g. the Terran ore contract to Earth). Expect
   `[MIC][OFFER] #N: player is in <sector>, creating a vanilla mission offer`, then "Procurement Contract" in
   Mission Offers. Accept it: expect `$MISSION_ACCEPTED` and "(accepted)" in the tab. Deliver: expect `[MIC][DONE]`
   and the premium paid once.
2. Sort (payout vs type) and the type filters with several factions listed.
3. Hidden path: the first ship (replenishment) contract, about one full cycle in, should log `-> [HIDDEN]` and stay
   out of the tab (needs contractor rank 1).
4. Whether the empty tab shows "No procurement contracts are open to you right now" before the first scan.

## Known issues / next

- Kha'ak materials (Allographyne, Allographyne Scrap) were picked for 3 of the first 6 contracts in testing. The
  generator should skip wares the player can't realistically supply.
- Antigone was counted with 99 stations; unverified whether that includes defence platforms or build sites.
- Ship replenishment contracts are listed but not offered yet (next milestone, via the game's fleet-delivery mission).
- Turn the test settings off before any release.

Full design, evidence and roadmap: [DESIGN.md](DESIGN.md).
