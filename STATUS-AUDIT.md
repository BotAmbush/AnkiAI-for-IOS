# AnkiAI iOS Migration — Status Audit

> ⚠️ **SUPERSEDED — point-in-time snapshot, not current.** This audit predates the
> **M2.1** milestone (real Anki collection read path via the Rust backend, CI green
> at run `28101322821`). For current status see `docs/progress.md`,
> `docs/feature-parity-checklist.md`, and `docs/known-issues.md`. Do not treat the
> percentages/blockers below as up to date (e.g. the M2.1 backend feasibility risk
> is now RESOLVED).

**Audit date:** 2026-06-24
**Audited by:** Claude (read-only audit; the only file created/modified is this `STATUS-AUDIT.md`)
**iOS project:** `C:\AnkiAI-for-IOS`
**Android source (read-only):** `C:\Users\Evyatar\AndroidStudioProjects\Anki-Android-AI`

> **Method note.** Facts below are labelled **[VERIFIED]** when taken directly from a command,
> log, or file inspected during this audit, and **[ESTIMATE]** when they are a judgement call.
> A green compile is **not** treated as functional completeness anywhere in this report.

---

# 1. Executive summary

- **Overall state [VERIFIED]:** Milestone 1 ("native AI layer + app shell + CI") is implemented and
  builds green on macOS CI. The Anki *core* (collection, scheduler, FSRS, sync, import/export) is
  **not implemented** — it is deferred to milestone 2, which reuses the upstream Rust `anki` backend.
  The app currently runs against an **in-memory collection stub**, not a real Anki collection.
- **Latest CI build succeeded? [VERIFIED]** Yes. Run #3, ID `28097004935`, conclusion `success`.
  Build SUCCEEDED, 38 unit tests passed (0 failures), unsigned IPA packaged and uploaded.
- **Valid unsigned IPA exists? [VERIFIED]** Yes. The executable is a real `Mach-O 64-bit arm64`
  iOS binary; the archive is a valid ZIP with `Payload/AnkiAI.app/`.
- **Exact IPA location [VERIFIED]:** `C:\AnkiAI-for-IOS\AnkiAI-unsigned.ipa` (297,638 bytes,
  downloaded from artifact `AnkiAI-unsigned-ipa` of run `28097004935`). It is git-ignored.
- **What genuinely works [VERIFIED by tests + CI]:** the native Claude API client (prompt caching,
  image blocks, usage→cost, error mapping), prompt construction, AI response parsing (edit/add-card
  actions + creator JSON array), HTML/math-aware text stripping, pricing/budget math, the AI Insights
  tip engine, the separate `ai_insights.db` chat store (system SQLite), and the reviewer/creator chat
  view models — all exercised by 38 passing unit tests and compiled for device.
- **What is scaffolding / incomplete [VERIFIED]:** everything that needs the real collection — deck
  list counts, card browser, editor, review queue + answer buttons, scheduler, FSRS, media,
  statistics, import/export, backups, sync, filtered decks, custom study, notifications, background
  behaviour, forced-study mode. The SwiftUI screens exist and render but operate on stub data. Live
  AI insights stats, creator image/PDF attachment UI, and bundled MathJax are also pending.
- **Single most important next step [ESTIMATE]:** Begin milestone 2 by building the upstream Rust
  `anki` backend as an iOS `xcframework` and implementing a `BackendCollectionGateway` behind the
  existing `CollectionGateway` seam. Without it, no core-Anki parity is possible.

---

# 2. Local Git repository status

Commands run (in `C:\AnkiAI-for-IOS`) and their **[VERIFIED]** output:

```text
$ git status --short --branch
## main...origin/main
        (no file lines → working tree clean, apart from this audit file being created)

$ git branch --show-current
main

$ git rev-parse HEAD
fcfecbba69061168130fc647adab79026ab30be2

$ git log --oneline --decorate -15
fcfecbb (HEAD -> main, origin/main) docs: record green M1 CI run (build + 38 tests + unsigned IPA)
a65dc65 fix: resolve async/throws in ?? autoclosure; abstract SecretStore for tests
c07ada7 ci: use macOS 15 + Xcode 16, create build dir, resolve simulator dynamically
4470a57 feat: bootstrap native iOS migration — analysis, AI layer, app shell, CI

$ git remote -v
origin  https://github.com/BotAmbush/AnkiAI-for-IOS.git (fetch)
origin  https://github.com/BotAmbush/AnkiAI-for-IOS.git (push)

$ git diff --stat
        (empty)

$ git diff --cached --stat
        (empty)

$ git rev-list --left-right --count origin/main...HEAD
0       0
```

**Interpretation [VERIFIED]:**
- Current branch: **main**
- Current commit SHA: **`fcfecbba69061168130fc647adab79026ab30be2`**
- Working tree: **clean** before this audit (the only new file is `STATUS-AUDIT.md`, which is the
  single permitted change; ignoring it, prior development work was fully committed).
- Uncommitted/untracked (pre-audit): **none** that are tracked-worthy. `AnkiAI-unsigned.ipa` exists
  locally but is git-ignored (`*.ipa`), so it is not an untracked change.
- Ahead/behind GitHub: **0 ahead, 0 behind** — local `main` equals `origin/main`.
- Remote URL: **https://github.com/BotAmbush/AnkiAI-for-IOS.git**

> Note: HEAD (`fcfecbb`) is a **docs-only** commit made *after* the commit that CI built
> (`a65dc65`). Verified: `git diff --name-only a65dc65 fcfecbb` lists only `docs/known-issues.md`
> and `docs/progress.md`. **The compiled code at HEAD is identical to the code that was built green.**

---

# 3. GitHub repository status

```text
$ gh auth status        (sanitized — no token shown)
✓ Logged in to github.com account BotAmbush (keyring)
- Active account: true
- Git operations protocol: https
- Token scopes: 'gist', 'read:org', 'repo'

$ gh repo view --json name,owner,visibility,url,defaultBranchRef
{
  "name": "AnkiAI-for-IOS",
  "owner": { "login": "BotAmbush" },
  "visibility": "PRIVATE",
  "url": "https://github.com/BotAmbush/AnkiAI-for-IOS",
  "defaultBranchRef": { "name": "main" }
}

$ gh workflow list
iOS Build & Test   active   301443097
```

**Confirmation [VERIFIED]:**
- **Owner:** personal account `BotAmbush` (a user account; `isInOrganization:false` was confirmed
  earlier during setup). **No organization is involved.**
- **Visibility:** PRIVATE
- **Default branch:** `main`
- **GitHub Actions enabled:** Yes — one active workflow, "iOS Build & Test" (id 301443097).
- **Workflow file used for iOS builds:** `.github/workflows/ios.yml`

No authentication tokens or secret values are reproduced in this report.

---

# 4. Complete GitHub Actions build history

`gh run list` returned **three** runs, all `event: workflow_dispatch`, all on workflow
"iOS Build & Test". **[VERIFIED]**

| Run # | Run ID | Commit SHA | Created (UTC) | Updated (UTC) | Conclusion | First actual failure cause | Repair applied afterward |
|------:|--------|-----------|---------------|---------------|------------|----------------------------|--------------------------|
| 1 | `28096644948` | `4470a57` | 2026-06-24 11:55:29 | 2026-06-24 11:56:01 | **failure** | `xcodebuild: error: Unable to read project 'AnkiAI.xcodeproj'. … future Xcode project file format (77)` — runner Xcode 15.4 cannot read the format XcodeGen emits. | Switched runner to `macos-15` and selected latest Xcode 16.x; added `mkdir -p build`; pick simulator UDID dynamically. (commit `c07ada7`) |
| 2 | `28096836686` | `c07ada7` | 2026-06-24 11:59:09 | 2026-06-24 11:59:50 | **failure** | `AnkiAI/AI/Chat/AIChatViewModel.swift:185:85: error: operator can throw but expression is not marked with 'try'` and `:185:99: error: 'async' call in an autoclosure that does not support concurrency` — `(try? await …) ?? (try await …)`. | Replaced `??`-over-async with optional-binding + else; added `SecretStore` protocol + `InMemorySecretStore` so tests don't need Keychain entitlements. (commit `a65dc65`) |
| 3 | `28097004935` | `a65dc65` | 2026-06-24 12:02:05 | 2026-06-24 12:04:51 | **success** | — | — |

### Latest run detail (run #3) — all **[VERIFIED]** from the run log

- **Run ID:** `28097004935`
- **URL:** https://github.com/BotAmbush/AnkiAI-for-IOS/actions/runs/28097004935
- **Commit SHA:** `a65dc6545c9027acc7b329c0a6d2b2f119907d91`
- **Status / conclusion:** completed / **success**
- **Runner image:** `macos-15-arm64` (Image Release `20260610.0126`)
- **macOS version:** macOS 15 (Sequoia), Apple silicon; build machine OS build `24G720`
- **Xcode version:** **16.4** (build `16F6`), iOS SDK **iPhoneOS 18.5**
- **Selected simulator:** UDID `18B3C1E7-6D31-4D90-8BF1-B155B4F66A9E` (chosen dynamically from
  available iPhone simulators)
- **Physical-device build destination:** `generic/platform=iOS`, configuration **Release**,
  `CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` → **`** BUILD SUCCEEDED **`**
- **Unit-test result:** **`** TEST SUCCEEDED **`** — `Executed 38 tests, with 0 failures (0 unexpected)`
- **UI-test result:** **none run.** No UI-test target exists; the workflow has a `run_ui_tests`
  input but no UI tests are wired. (Verified: no `AnkiAIUITests` directory/target.)
- **Device build result:** SUCCEEDED (Release-iphoneos, arm64; `GenerateDSYMFile` + `dsymutil` ran)
- **IPA packaging result:** `Built IPA: -rw-r--r-- … 297638 … build/AnkiAI-unsigned.ipa`
- **Artifact upload result:** `AnkiAI-unsigned-ipa` uploaded (294,555 bytes, artifact id 7848897235);
  `diagnostics` uploaded (1,093,590 bytes, artifact id 7848897725)

---

# 5. Artifact and IPA verification

**Artifacts from the latest successful run (`28097004935`) [VERIFIED]:**

| Artifact name | Size (bytes) | Contents |
|---|---|---|
| `AnkiAI-unsigned-ipa` | 294,555 | `AnkiAI-unsigned.ipa` |
| `diagnostics` | 1,093,590 | build/test logs, `TestResults.xcresult`, `dSYMs/` (includes `AnkiAI.app.dSYM`) |

**Locally downloaded [VERIFIED]:** `AnkiAI-unsigned.ipa` → `C:\AnkiAI-for-IOS\AnkiAI-unsigned.ipa`.
The `diagnostics` artifact was **not** downloaded locally.

**IPA verification — all [VERIFIED] via `unzip`, `xxd`, `file`, and `plistlib`:**

| Property | Result |
|---|---|
| Filename | `AnkiAI-unsigned.ipa` |
| GitHub artifact name | `AnkiAI-unsigned-ipa` |
| Local path | `C:\AnkiAI-for-IOS\AnkiAI-unsigned.ipa` |
| File size | 297,638 bytes |
| Non-empty | Yes |
| Opens as ZIP | Yes (`unzip -t` → archive OK) |
| `Payload/` exists | Yes |
| `.app` bundle path | `Payload/AnkiAI.app/` |
| Executable filename | `AnkiAI` (1,225,424 bytes) |
| Compiled Mach-O iOS binary | Yes — magic `cf fa ed fe`; `file` → **Mach-O 64-bit arm64 executable** (flags NOUNDEFS, DYLDLINK, TWOLEVEL, PIE) |
| Bundle identifier | `com.evyatar.ankiai` |
| Minimum iOS version | `MinimumOSVersion = 16.0` |
| Supported device families | `UIDeviceFamily = [1, 2]` (iPhone + iPad) |
| Signing absent/disabled as intended | Yes — **no** `embedded.mobileprovision`, **no** `_CodeSignature/` directory |
| dSYM output exists | Yes — `AnkiAI.app.dSYM` generated in CI and included in the `diagnostics` artifact (not inside the IPA, which is correct) |

Additional plist facts [VERIFIED]: `CFBundleShortVersionString = 0.1.0`, `CFBundleVersion = 1`,
`DTPlatformName = iphoneos`, `DTPlatformVersion = 18.5`, `DTXcode = 1640`.

The IPA was **not** signed or installed during this audit.

---

# 6. Current project structure

**Counts [VERIFIED]:** 22 Swift source files (app), 6 Swift unit-test files, **0** UI-test files.
**External Swift packages / third-party dependencies: none** (no `Package.swift`, no `Podfile`,
`project.yml` `dependencies: []`). The AI database uses the OS `libsqlite3`; networking uses
`URLSession`.

**Main source directories [VERIFIED]:** `AnkiAI/{App, AI/{Provider,Chat,Insights}, Domain,
Features/{Decks,Reviewer,Chat,Insights,Settings}, Persistence, Security, Rendering}`,
`AnkiAITests/`.

Classification (**functional** = implemented + tested/rendered; **partial** = real code but
incomplete or stub-backed; **placeholder** = exists, minimal; **not started**; **blocked** = waiting
on the Rust backend). Functionality judged from code + tests, **not** filenames.

| Item | Status | Evidence / note |
|---|---|---|
| Xcode project / workspace | functional (generated) | `AnkiAI.xcodeproj` is generated by XcodeGen in CI and git-ignored; built green |
| XcodeGen `project.yml` | functional | drives CI generation; verified |
| Swift app entry point | functional | `App/AnkiAIApp.swift` (`@main`), compiles |
| SwiftUI navigation shell | functional | `App/RootView.swift` TabView (Decks/Insights/Settings); compiles, renders |
| Deck list | partial | `Features/Decks/DeckListView.swift` lists stub decks; no real counts/queues |
| Card browser | not started | — |
| Note/card editor | partial | only the AI edit-proposal path against the stub; no general editor |
| Review screen | partial | `Features/Reviewer/ReviewerView.swift` renders front/back + Ask Claude; no answer buttons/queue |
| Domain models | functional (M1 scope) | `Domain/DomainModels.swift` value types + `CollectionGateway`; used by passing tests |
| Persistence layer | partial | `Persistence/{SQLiteDatabase,AIDatabase}.swift` — only `ai_insights.db` chat table (tested); not the Anki collection |
| Collection handling | blocked | only `StubCollectionGateway` (in-memory); real collection = Rust backend (M2) |
| Scheduler | blocked / not started | M2 (Rust backend) |
| FSRS | blocked / not started | M2 (Rust backend) |
| HTML rendering | partial | `Rendering/CardWebView.swift` (WKWebView) renders raw HTML; full template/CSS via backend M2 |
| MathJax rendering | partial | configured for `\(\)`/`\[\]`; loads MathJax from **CDN** (needs network), not bundled |
| Hebrew / RTL support | functional (rendering+text) | `dir` preserved; `HTMLText` math/RTL strip tested; not yet localized UI strings |
| Mixed RTL/LTR handling | functional (rendering) | per-span `dir` honored in renderer + prompts |
| Media handling | not started | Anki media store M2; AI image *transport* exists (client) but no capture UI |
| Statistics | not started | M2 |
| Import/export | not started | M2 (backend) |
| Backups / restore | not started | M2 (backend) |
| Synchronization | not started | M2 (backend) |
| Filtered decks | not started | M2 |
| Custom study | not started | M2 |
| Notifications | not started | M3 |
| Background behavior | not started | M3 |
| AI card-generation workflow | functional (logic) | creator VM: prompt → JSON array → proposals → add; tested. UI sheet present; image attach UI pending |
| Claude / API integration | functional | `AI/Provider/ClaudeAPIClient.swift`; request shaping/caching/usage tested with fake transport |
| Prompt management | functional | `AI/Prompts.swift` ported verbatim; used by tests |
| Keychain / secret storage | functional (production path) | `Security/KeychainStore.swift` (`SecretStore`); used by the app; tests use in-memory variant |
| Settings | partial | `Features/Settings/AISettingsView.swift` — AI key/test/budget done; collection prefs M2 |
| Unit tests | functional | 6 files, 38 tests, all passing in CI |
| UI tests | not started | no UI-test target |
| GitHub Actions workflow | functional | `.github/workflows/ios.yml`; green run verified |
| IPA packaging scripts | functional | packaging is inline in the workflow; `tools/generate-project.sh` + `tools/secret-scan.sh` exist |

---

# 7. Documentation status

All required docs exist **[VERIFIED]** (line/byte counts measured this audit). "Complete" = covers
its topic with current, accurate content for M1; "partial" = real but thin / will grow as features
land. None are placeholders or missing.

| File | Lines | Status | Notes |
|---|---:|---|---|
| `CLAUDE.md` | 447 | complete | project charter (provided) |
| `README.md` | 47 | complete | honest status, build/install pointers |
| `docs/progress.md` | 69 | complete | canonical ledger; records green CI |
| `docs/feature-parity-checklist.md` | 65 | complete | per-feature status table |
| `docs/known-issues.md` | 28 | complete | honest limitations incl. CI/IPA |
| `docs/android-inventory.md` | 35 | complete (M1 depth) | modules, backend finding, AI surface |
| `docs/screen-and-navigation-map.md` | 24 | partial | covers implemented + planned screens |
| `docs/database-and-data-model.md` | 40 | complete (M1 depth) | two-DB separation, AI schema |
| `docs/scheduler-and-fsrs-analysis.md` | 30 | partial | analysis only; impl is M2 |
| `docs/import-export-analysis.md` | 19 | partial | analysis only; impl is M2 |
| `docs/sync-analysis.md` | 21 | partial | analysis only; impl is M2 |
| `docs/media-analysis.md` | 23 | partial | analysis + AI image transport note |
| `docs/ai-feature-analysis.md` | 41 | complete | per-file Android→iOS mapping + status |
| `docs/ios-architecture.md` | 50 | complete | layering, gateway seam, backend plan |
| `docs/migration-risks.md` | 15 | complete | R1–R11 risk table |
| `docs/licensing-analysis.md` | 31 | complete | GPL/AGPL analysis + open item |
| `docs/implementation-roadmap.md` | 39 | complete | M1–M3 slices |
| `docs/decision-log.md` | 40 | complete | DL-001…DL-008 |
| `BUILDING.md` | 46 | complete | local + CI build paths |
| `TESTING.md` | 39 | complete | suites mapped to requirements |
| `INSTALLING-IPA.md` | 26 | complete | iLoader sideload steps |

(Also present: `SECURITY.md` 26, `CONTRIBUTING.md` 29, `LICENSES.md` 14, `THIRD_PARTY_NOTICES.md` 30.)

---

# 8. Feature-parity assessment

Scope reference [VERIFIED]: the Android fork's custom AI code is `com.ichi2.anki.ai.*` (29 Kotlin
files across api/chat/data/insights/analytics/settings/enforcement/hints/update), atop a full
AnkiDroid app (681 Kotlin files) whose core is the Rust backend (`anki-android-backend`).

**Counts by category** (CLAUDE.md feature list + AI features; **[ESTIMATE]** classification informed
by verified evidence):

| Category | Count |
|---|---:|
| Completed (implemented **and** tested/CI-verified) | **9** |
| Partially implemented | **9** |
| Placeholder only | **0** |
| Not started | **~24** |
| Blocked (need Rust backend) | **~12** (overlaps "not started") |
| Unsupported / partial-by-platform | **1** (forced-study enforcement) |

### Completed features (with evidence)

1. **Claude API client / provider integration** — `AI/Provider/ClaudeAPIClient.swift`;
   `AnkiAITests/ClaudeAPIClientTests.swift` (headers, prompt-caching `system` array, image blocks,
   usage parsing, 401/529 mapping); compiled in CI.
2. **Prompt management** — `AI/Prompts.swift`; asserted via `AIChatViewModelTests`
   (system prompt contains card context); CI-compiled.
3. **AI response parsing (edit/add/creator)** — `AI/AIModels.swift`;
   `AIResponseParserTests` (10 tests incl. malformed-JSON fallback).
4. **HTML / math-aware text handling (incl. Hebrew)** — `AI/HTMLText.swift`; `HTMLTextTests`.
5. **Pricing / budget + error presenter** — `AI/AIBudget.swift`; `PricingAndTipsTests`.
6. **AI Insights tip engine** — `AI/Insights/AITipEngine.swift`; `PricingAndTipsTests`
   (top-5 cap, priority sort, streak-zero). *Live stats are NOT done (needs revlog).*
7. **AI chat persistence (`ai_insights.db`)** — `Persistence/{AIDatabase,SQLiteDatabase}.swift`;
   `AIDatabaseTests` (ordering, delete, metadata round-trip).
8. **Reviewer + creator chat view models** — `AI/Chat/AIChatViewModel.swift`;
   `AIChatViewModelTests` (plain reply persisted, edit proposal surfaced + applied, creator parsing,
   spend tracked, error surfaced) — against the **stub** gateway.
9. **Keychain/secret storage (production path) + CI build/test/IPA pipeline** —
   `Security/KeychainStore.swift`; `.github/workflows/ios.yml`; green run `28097004935`.

> Caveat [VERIFIED reasoning]: every "completed" item is validated against fakes/stubs and an
> in-memory collection — **not** against a real Anki collection, real network calls, or on a
> physical device. They are complete **as M1 units**, not as end-to-end product features.

### 15 highest-priority missing / partial features [ESTIMATE]

1. Rust `anki` backend `xcframework` + Swift `libanki` wrapper (unblocks everything below)
2. Real collection open/close & `BackendCollectionGateway`
3. Scheduler (queues, answer buttons, learning/review/relearn steps)
4. FSRS behaviour & configuration
5. Decks/subdecks with real counts + deck list wiring
6. Review screen end-to-end (answer, undo, bury, suspend)
7. Card template/CSS rendering (`render_card`) + media serving to WebView
8. Card browser
9. Note/card editor (general)
10. Synchronization / AnkiWeb (Keychain creds)
11. Import/export (`.apkg`/`.colpkg`) + backups/restore
12. Statistics
13. Live AI Insights stats (`RevlogAnalyzer` + `ai_card_meta`/`ai_study_log`)
14. Creator image/PDF attachment capture (PhotosPicker + PDFKit) — transport already exists
15. Bundled MathJax (offline) + UI localization (Hebrew/RTL strings)

---

# 9. Android source safety verification

Read-only commands run this audit **[VERIFIED]**:

```text
$ git -C "C:\Users\Evyatar\AndroidStudioProjects\Anki-Android-AI" rev-parse HEAD
9bad8304c8b7b013a6c977c20ebd9f726a436430

$ git -C "C:\Users\Evyatar\AndroidStudioProjects\Anki-Android-AI" status --short
?? .claude/settings.local.json
?? Anki-Android-AI-layer.zip
?? <many pre-existing .png / .xml / .md screenshots and UI dumps>
   (untracked only; NO tracked modifications)

$ git -C "…" status --porcelain --untracked-files=no
   (empty — zero tracked changes)
```

| Item | Value |
|---|---|
| Original baseline HEAD (captured at start) | `9bad8304c8b7b013a6c977c20ebd9f726a436430` |
| Current HEAD | `9bad8304c8b7b013a6c977c20ebd9f726a436430` |
| HEAD changed? | **No** |
| Baseline working-tree status | untracked screenshots/XML/zip + `.claude/settings.local.json`; no tracked changes |
| Current working-tree status | **identical** set of untracked files; no tracked changes |
| Did Claude create/modify anything in the Android repo? | **No** |
| Android project safe & unchanged? | **Yes — verified unchanged** |

No reset/clean/restore/checkout/stash/format/build/alter was performed on the Android repository at
any point.

---

# 10. Security and licensing

- **Secrets in tracked files? [VERIFIED]** None. A scan for `sk-ant-[A-Za-z0-9_-]{20,}` over all
  tracked files found only the literal test placeholder `"sk-ant-test"` in
  `AnkiAITests/AIChatViewModelTests.swift` (a fake string, not a credential). No real keys.
- **Secret scanning exists? [VERIFIED]** Yes — `tools/secret-scan.sh` (patterns for Anthropic keys,
  AWS keys, PEM private keys; excludes placeholder strings).
- **API keys hard-coded? [VERIFIED]** No. The only `apiKey = "sk-ant-…"` literals are the test
  placeholder above. The app reads the key from the Keychain at runtime.
- **Keychain functional or planned? [VERIFIED—nuanced]** The production `KeychainStore`
  (Security framework, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) is implemented and used
  by the app. It is **not** exercised by automated tests (tests inject `InMemorySecretStore`), so its
  on-device behaviour is **unverified by CI** — it requires physical-device/host-app validation.
- **Credentials in logs? [VERIFIED reasoning]** The client does not log the key; debug logging was
  not ported. Low risk, but not formally audited end-to-end.
- **Android/AnkiDroid-derived code copied? [VERIFIED]** No source files were copied. The AI logic and
  prompts were **conceptually re-implemented** in Swift; prompts are reproduced verbatim as strings
  (data, attributed). Origin is disclosed in `README`, `THIRD_PARTY_NOTICES.md`, `docs/licensing-analysis.md`.
- **Licensing obligations [VERIFIED facts / ESTIMATE on obligation]:** This is a derivative of
  GPL-3.0 AnkiDroid → the iOS port is **GPL-3.0**. The planned Rust `anki` backend is **AGPL-3.0**,
  which carries stronger network/distribution obligations.
- **`THIRD_PARTY_NOTICES.md` exists? [VERIFIED]** Yes. **`LICENSES.md` exists? [VERIFIED]** Yes.
- **Unresolved licensing risks [VERIFIED as open item]:** (a) AGPL implications of distributing the
  Rust backend in an iOS app are **not yet resolved** (tracked in `docs/licensing-analysis.md`);
  (b) `COPYING` (full GPL text) is referenced but not yet added; (c) MathJax (Apache-2.0) is loaded
  from CDN rather than bundled with its notice.

No secret values are printed anywhere in this report.

---

# 11. Honest completion percentages

Conservative **[ESTIMATE]s**. A green build is explicitly **not** treated as functional parity.

| Dimension | % | Justification |
|---|---:|---|
| Android-project analysis | **70%** | AI fork read in depth; core-vs-backend boundary identified; full per-screen/DB-column enumeration of the 681-file app not exhaustive |
| Build & CI infrastructure | **85%** | green build+test+unsigned-IPA+artifacts; missing: UI tests, signing path, Rust build step |
| Native iOS app shell | **60%** | navigation + 5 screens render; operate on stub data; no deep linking/state restoration |
| Total functional parity | **5–8%** | only AI-layer units done; all core Anki features absent |
| Persistence & data compatibility | **5%** | AI side-DB works; the Anki collection (the compatibility-critical part) is untouched |
| Scheduler & FSRS parity | **0%** | not started (backend) |
| Import/export compatibility | **0%** | not started (backend) |
| Synchronization parity | **0%** | not started (backend) |
| AI functionality parity | **55%** | client/prompts/parsing/chat/creator/insights-engine done & tested; missing: live insights stats, image/PDF attach UI, forced-study, real-collection writes, on-device validation |
| Automated test coverage | **35%** | strong for AI/parsing/db logic (38 tests); none for UI, Keychain on-device, or any core feature |
| Readiness to install on a physical iPhone | **60%** | valid unsigned arm64 IPA exists; still needs user signing (iLoader) + trust; not yet validated on a device |
| Readiness for meaningful physical-device testing | **20%** | installs and AI flow *should* work with a key, but there is no real collection to test against |
| Readiness for everyday use | **3%** | cannot manage/review/sync real cards |
| Readiness for release | **2%** | core absent; AGPL/license items open; no signing/store path |

---

# 12. Current blockers and risks

**Build blockers [VERIFIED]:** none currently — CI is green at HEAD's code.

**Runtime blockers [VERIFIED / ESTIMATE]:**
- No real collection → decks/review/browser/stats/sync are non-functional at runtime (stub only).
- MathJax requires network (CDN) → math won't render offline.
- AI features require a user-supplied Claude key + network; without a key the chat/creator are inert.
- Keychain read/write is unvalidated on-device (tests bypass it).

**Data-loss risks [ESTIMATE]:** Low today (the app does not yet open real collections). The **future**
risk is high if the M2 backend integration is done incorrectly — hence the decision to reuse the
canonical Rust backend rather than reimplement, to preserve `collection.anki2`/sync integrity.

**Migration risks [VERIFIED from docs]:** R1 building the Rust xcframework (high); R2 forced-study
cannot match Android's always-on overlay/foreground service on iOS (partial parity); R3 background
timing differs; others in `docs/migration-risks.md`.

**Licensing risks [VERIFIED open items]:** AGPL distribution of the Rust backend; missing `COPYING`;
CDN MathJax notice.

**Features requiring physical-device testing [ESTIMATE]:** Keychain persistence, WKWebView/MathJax
rendering fidelity, RTL layout on-device, camera/photo attachment, notifications/background, and (at
M2) sync and media.

**Features that may need Apple entitlements / paid capabilities [ESTIMATE]:** code signing for
install (user-side via iLoader/free team), push/background modes, Keychain access groups, App Store
distribution (paid program). None are required for the current unsigned-IPA sideload path.

**Unvalidated assumptions [ESTIMATE]:** that the Rust `anki` backend will cross-compile cleanly to an
iOS xcframework with a usable Swift bridge; that the fork's exact Claude model IDs remain valid; that
iOS background limits will allow an acceptable forced-study analog; that Keychain works in the
sideloaded/unsigned context.

---

# 13. Recommended next phase

**Recommended immediate step [ESTIMATE]:** **continued Claude implementation**, starting milestone 2
(Rust `anki` backend integration). This is the critical path and unblocks the ~12 blocked core
features. An independent review (e.g. Codex) and a formal **licensing review** of the AGPL backend
are valuable in parallel, and the AGPL question should be resolved **before** any binary distribution
beyond private sideloading. More CI build-repair is **not** needed (CI is green); physical-device
testing is premature until there is a real collection to exercise.

**Recommended milestone — M2.1 "Collection read path on device":**
Build `AnkiCore.xcframework` from a pinned upstream `anki` commit, add a minimal Swift wrapper, and
implement a `BackendCollectionGateway` that **opens a real `collection.anki2` and lists decks with
live new/learning/review counts**, replacing `StubCollectionGateway`.

**Definition of completion for M2.1 (all must hold):**
1. CI builds the Rust `xcframework` on the macOS runner and links it into the app (still unsigned).
2. The app opens a real test `collection.anki2` (fixture, legally sourced) without modifying schema.
3. The deck list shows real deck names **and** correct new/learning/review counts from the backend.
4. A unit/integration test opens a fixture collection and asserts deck names + counts (no device).
5. A sync-contract-style test asserts the Anki schema is unchanged after open/close.
6. The green CI run still produces the unsigned IPA, now containing the backend.
7. `docs/progress.md` + parity checklist updated; Android source re-verified unchanged.

---

*End of audit. This report did not modify any file other than `STATUS-AUDIT.md`, ran no builds,
triggered no workflows, installed nothing, and made no changes to the Android repository.*
