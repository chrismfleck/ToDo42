# Multiple pairs (parked)

Parked 30 Aug 2026. Do not build until Chris asks.

## Goal

Chris can keep **one list with Deena** and a **separate list with Brian**. A new pair must never replace or wipe another list.

## How it should feel

- Home list switcher: **Deena** and **Brian**.
- Open Deena: only that list. Open Brian: a separate list.
- Pair phones shows both. **Invite Brian** makes a new list. It does not touch Deena.
- Hearts and names are only for the pair you are looking at.
- Unpair Brian leaves Deena as-is.

## What has to change

1. **Tag every item with a list id.** CloudKit already has `pairID` on items. The phone does not. Existing items stay on the Deena list. New Brian items get a new id.
2. **Remember more than one pair.** Store Deena and Brian (names, role, invite code, list id). “Active list” is which one you are viewing.
3. **Sync only the open list.** Pull/push Deena items for Deena, Brian items for Brian. Never delete an item because another list is empty. That is the unpair-and-new-invite wipe, fixed for good.
4. **Keep two-person hearts per list.** Internally still host/guest (`chrisHearted` / `deenaHearted` on that list). On Brian’s list, Deena is not a heart. Labels stay the names you type.
5. **Pair screen.** List of pairs, plus **Add a pair**. Invite or join a code for that pair only.

## What we should not do

- Do not unpair Deena to add Brian.
- Do not make one shared pile of items for everyone.
- Do not add a third heart on a two-person list.
- Do not ship this until restore + “new invite does not wipe” is on both phones.

## Build order

1. Put `pairID` on local items and stop prune-across-lists. No new UI yet. Chris and Deena keep using the same list.
2. Add the list switcher and “Add a pair.” Create Brian’s list as empty and separate. Confirm Deena’s list is unchanged.
3. Invite Brian. Confirm his items do not appear on Deena’s list, and hers do not appear on his.
4. TestFlight for Chris, then Deena, then Brian.

## Chris on the phone

- Deena list = what they have now.
- Brian list = new invite, new code, only Brian joins that code.
- Same iCloud. Do not unpair Deena.
