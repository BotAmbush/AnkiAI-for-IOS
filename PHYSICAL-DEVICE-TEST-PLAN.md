# AnkiAI — Physical-Device Test Plan

## ✅ Already PASSED on a physical device (2026-06-25)
- Full AnkiWeb **download** · **media** download
- **Demo/seeded upload blocking** (the sample collection cannot replace AnkiWeb)
- Normal **two-way sync**
- **Persistence** after force-closing and reopening
- **Learning/relearning** card returning after the displayed short delay
- **MathJax** rendering

> Recorded as `physical_device_verified: true` in the feature map. Full **upload**
> is NOT physically verified (and is intentionally guarded).

## 🔁 MUST be RE-TESTED on device (fixed in this repair, not yet device-verified)
- **Manual backup** now saved to On My iPhone/AnkiAI/Backups (Files-visible) — steps 13–14.
- **Manual Add Card** entry point (Decks → "+" Add card) — new step.
- **Logout / initial auth UI** (demo never shown as logged in; Logout works now) — steps 1–3 + a logout.

---

Run this **ordered** sequence on a real iPhone after installing the latest unsigned
IPA (signed with iLoader). Record each step as **PASS / FAIL / NOT TESTED** in the
table at the bottom. Nothing is "device-verified" until this is executed.

## ⚠️ Safety rule (read first)
Before ANY destructive step (full download, upload, restore), you MUST have a
**verified external backup of your real collection** — sync your real collection to
AnkiWeb from Anki Desktop/AnkiDroid, and/or export a `.colpkg` from Anki Desktop and
keep it safe. The app also keeps local backups, but do not rely on them alone.

The app blocks the most dangerous action by default: **uploading the demo/sample
collection to AnkiWeb is forbidden** (see step 3). Do not try to bypass it.

## Ordered test sequence

| # | Step | What to check |
|---|------|---------------|
| 1 | **Fresh install** | App launches; Decks tab shows the seeded demo decks. |
| 2 | **Seeded collection identification** | Settings → AnkiWeb sync shows "This phone's collection: Demo / sample (not your data)". |
| 3 | **Upload blocked for seeded collection** | While still on the demo collection, confirm there is NO working "Upload to AnkiWeb" path (it's blocked / shows the red "upload is BLOCKED" note). |
| 4 | **External backup verification** | Confirm you have a real AnkiWeb/desktop backup of your actual collection BEFORE proceeding. |
| 5 | **AnkiWeb login** | Settings → enter email/password → "Log in". Login succeeds (no error). |
| 6 | **Full download** | When prompted for a direction, choose ⬇︎ Download. It completes; Decks tab shows YOUR real decks; provenance now "From AnkiWeb". |
| 7 | **Relaunch & persistence** | Force-quit and reopen; your real collection is still there. |
| 8 | **Two-way sync** | Make a small change (e.g., review one card), tap "Sync now"; it reports success. |
| 9 | **Media sync** | Open a card that has an image/audio; the image displays / audio plays. |
| 10 | **Add/edit/review on iPhone** | Review a few cards; answer Again/Hard/Good/Easy; edit a card (fields + tags + deck); answers persist after leaving the reviewer. Suspended/not-due cards do NOT appear. |
| 11 | **Sync changes back safely** | "Sync now" pushes your iPhone changes; verify on Anki Desktop/AnkiWeb that the changes arrived and nothing else was lost. |
| 12 | **APKG import** | Try importing a `.apkg` (KNOWN LIMITATION: may fail with an anki deck-merge error — if so, it must fail gracefully and your collection must be unchanged). |
| 13 | **Backup** | Settings → "Back up collection (.colpkg)"; a file appears in the app's Documents (Files app). |
| 14 | **Restore** | Settings → "Restore from .colpkg"; pick the backup; the collection restores. |
| 15 | **Keychain persistence** | Relaunch; AnkiWeb session + Claude key persist (no re-login needed). |
| 16 | **HTML / MathJax / RTL** | A Hebrew/RTL card renders right-to-left; a MathJax card renders the formula; offline (airplane mode) math still renders. |
| 17 | **AI reviewer chat** | In review, "Ask Claude" answers with card context (Claude key required); "improve card" applies a real edit. |
| 18 | **AI creator** | Create cards with AI from a prompt (+ optional photo/PDF); proposals add real cards; a `{{c1::…}}` proposal becomes a Cloze card. |
| 19 | **AI Insights** | Insights shows real numbers (streak, reviews/day, retention, charts) from your actual collection. |

## Results

| # | Result (PASS / FAIL / NOT TESTED) | Notes |
|---|---|---|
| 1 |  |  |
| 2 |  |  |
| 3 |  |  |
| 4 |  |  |
| 5 |  |  |
| 6 |  |  |
| 7 |  |  |
| 8 |  |  |
| 9 |  |  |
| 10 |  |  |
| 11 |  |  |
| 12 |  |  |
| 13 |  |  |
| 14 |  |  |
| 15 |  |  |
| 16 |  |  |
| 17 |  |  |
| 18 |  |  |
| 19 |  |  |

> Until steps 5–11 (sync + review + safe push-back) and 16 PASS on a real device,
> `synchronization` and the migration as a whole stay **partial / not finalized**.
