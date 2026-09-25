# Multiple pairs

Building on `cursor/save4two-unified-ac25` (unlocked Sep 2026).

## Locked decisions (Chris)

1. **Pairs first** (avatars/photos after multi-pair works).
2. **Home switch:** tap a **head** beside the title to switch lists (generic heads until photos).
3. **Share (Instagram etc.):** **silent last-open** — share extension uses `activePairID` from App Group; no pair picker in the sheet.
4. **Hearts:** still **two per list** (me + that partner only).
5. **Unpair:** unpair one pair leaves the other untouched.

## Goal

Keep **one list with Deena** and a **separate list with Diane** (or Brian). A new pair must never replace or wipe another list.

## How it should feel

- Pair page: list of pairs when 2+, plus **Add a pair**. First pair same as today.
- Home header: `[partner head]  Save 4 Two  [my head]` for the active pair; tap a head to switch.
- Instagram share → active (last-open) list only.
- Hearts and names only for the open pair.
- Unpair Diane leaves Deena as-is.

## What has to change

1. **Tag every item with `pairID`.** CloudKit already has it; local SwiftData must too. Existing items stay on the current pair.
2. **Remember more than one pair** (names, role, invite code, list id, optional later photos). `activePairID` = viewing + sharing target.
3. **Sync only the open list.** Never prune/delete across lists.
4. **Two-person hearts per list** (`chrisHearted` / `deenaHearted` = host/guest on that list).
5. **Pair screen** + **header heads** to switch.

## Build order

1. ~~`pairID` on local items + stop prune-across-lists. Migrate existing items to current pair.~~
2. ~~Multi-pair session + pair list UI + Add pair; active pair switch.~~
3. ~~Home header heads (generic) to switch; share targets `activePairID` (App Group mirror; import stamps active pair).~~
4. Optional: pick local profile photos for heads.
5. TestFlight: Chris ↔ Deena, then second pair.

## Implemented

- `TodoItem.pairID` + migrate empty → active pair
- `PairSession.savedPairs`, `beginAddPair` / `switchToPair` / unpair-one-only
- App Group `todo42.activePairID` for last-open share targeting
- CloudSync push/prune scoped to active pair
- PairingView pair list + Add a pair
- Home generic initials heads to cycle pairs when 2+
