# Plan: Save to Save4Two + text partner (one share)

## Goal

From Instagram / Safari / etc., let someone **save into Save4Two and optionally text their partner in the same flow** — without selecting Messages as a second share-sheet destination.

Mocked UX (accepted direction):

1. System share sheet → **Save4Two**
2. Extension form: preview, categories, **Save**
3. Toggle **Also text to partner** (default on when a partner number exists)
4. Item lands in Save4Two inbox (unchanged import path)
5. If toggle on → Messages opens to the partner with a short note + the original link

iOS share sheets are one destination at a time, so “Save4Two then text” must live **inside** our extension (or main app), not as dual selection of Save4Two + Messages.

---

## Current building blocks

| Piece | Today | Role in this feature |
|-------|--------|----------------------|
| `ShareExtension/ShareViewController.swift` | Extracts URL/title/image; hosts `ShareFormView` | Add toggle + post-save Messages handoff |
| `ShareFormView` | Form → `onSave(SharePayload, image)` → `ShareInbox.save` → `completeRequest` | UI for **Also text to partner** |
| `ToDo42/ShareInbox.swift` + App Group `group.com.chrisfleck.ToDo42` | Draft JSON/images for main app | Unchanged save path; also store partner phone for extension |
| `PairSession` / `PairingView` | Names, invite codes, multi-pair | Capture optional **partner mobile**; mirror into App Group |
| CloudKit sync / push | Partner sees new item after main app uploads | Independent of SMS; keep both |

There is **no** partner phone number or `MFMessageCompose` usage in the app today.

---

## Product rules (v1)

1. **Save always happens** when the user taps Save (same inbox behavior as now).
2. **Text is optional** via toggle; Off = save only.
3. Toggle defaults **On** only if a usable partner phone is stored; otherwise Off / hidden with a one-line hint: “Add partner’s number in Pair”.
4. Message body (v1): `Saved this for us in Save4Two` plus the **original page URL** (so Messages shows a normal rich preview).
5. Do **not** require `save4two.app` deep-link cards in v1 (needs hosted OG pages + stable item IDs the extension does not have yet).
6. Multi-pair v1: text the partner for the **active** pair only (same App Group active-pair key already mirrored).
7. If Messages cannot send (no SIM, iPad, simulator): save still succeeds; show a short failure and dismiss.

---

## Implementation slices

### Slice A — Partner phone (main app)

**Files:** `PairingView.swift`, `PairSession` / `CloudSync.swift` (session fields), App Group defaults.

- Add optional field **Partner’s mobile** on the pairing / names card.
- Persist per active pair (alongside `myName` / `partnerName`), e.g. `todo42.partnerPhone` + per-profile in `savedPairs` if multi-pair.
- Normalize to digits / E.164-ish string for `sms:` / message composer.
- Mirror into App Group (`UserDefaults(suiteName: AppGroup.id)`) whenever pair/phone changes so the extension can read it without launching the main app.
- Do **not** upload phone to CloudKit in v1 (privacy; on-device only).

**Acceptance:** After entering a number in Pair, force-quit app; Share Extension can still read that number from the App Group.

### Slice B — Share Extension UI + handoff

**Files:** `ShareExtension/ShareViewController.swift` (`ShareFormView`), possibly a tiny `PartnerTextHandoff` helper in the extension target.

- Below Save (or in a footer section): toggle **Also text to partner**.
- On Save:
  1. `ShareInbox.save(payload:image:)` as today.
  2. If toggle on and phone present → present `MFMessageComposeViewController` with `recipients` + `body` (note + URL).
  3. On composer finish / cancel → `extensionContext?.completeRequest(...)`.
  4. If `CFMessageComposeViewController.canSendText()` is false → try `sms:<number>&body=` open, else complete after save with no text.
- Keep the extension free of CloudKit / SwiftData.

**Acceptance:** Instagram → Save4Two → Save with toggle On → Messages sheet shows partner + prefilled text + link; item still appears in Save4Two after opening the main app.

### Slice C — Polish & Help

- Help step: “Share to Save4Two, optionally text your partner.”
- Pair empty-state copy when phone missing.
- Accessibility labels for the toggle.
- Manual test matrix: Instagram, Safari, Airbnb; iPhone with Messages; airplane / no SMS.

---

## v2 (out of scope for first ship)

- Hosted `https://save4two.com/i/<id>` cards with Save4Two branding (needs API + OG HTML after main-app CloudKit save).
- “Text partner” from item detail inside the main app.
- Pick which pair/partner when multiple pairs exist.
- Sync partner phone via CloudKit (optional, privacy review).

---

## Risks

| Risk | Mitigation |
|------|------------|
| Share extension dismissed before Messages finishes | Present composer **before** `completeRequest`; only complete on composer delegate |
| Instagram share lifecycle quirks | Test on device; keep handoff minimal |
| Stale / wrong pair phone with multi-pair | Key phone by `activePairID` in App Group |
| Users expect push = text | Copy: text is a personal SMS; Save4Two push still notifies inside the app |
| App Review / SMS | Standard Messages compose; no auto-send without user tapping Send |

---

## Suggested build / ship order

1. Slice A (phone field + App Group) — can ship alone, no share UX yet  
2. Slice B (toggle + Messages) — feature complete for mockups  
3. Slice C (Help + QA) → bump marketing train (e.g. 1.0.5+) and submit  

No change to Chrome desktop extension for v1; that path stays “send URL to phone inbox” only.

---

## Done means (this plan)

- [x] User flow aligned with mockups  
- [x] Grounded in current Share Extension + App Group + Pairing  
- [x] v1 vs v2 split, acceptance criteria, risks  
- [x] Implementation (branch `cursor/save-text-partner-ac25`)  
