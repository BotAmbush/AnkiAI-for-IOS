# Migration Risks

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | ~~Building Rust `anki` rslib as an iOS xcframework~~ | **RESOLVED (M2.1)** | Proven in CI: pinned anki `25.09.2` + bridge compile for both iOS targets and assemble `AnkiCore.xcframework`; app links it (IPA arm64). Build-script gotchas fixed (submodules, tokio io-util, anki_proto-first, no cache). See `docs/anki-backend-ios-feasibility.md`. Remaining backend surface (scheduler/sync/etc.) reuses the same proven path. |
| R2 | **Forced-study enforcement** cannot match Android | Medium | iOS has no `TYPE_APPLICATION_OVERLAY` / always-on foreground service and restricts background exec. Use local notifications + an in-app enforced session + optional Screen Time API exploration. Document as **partial parity** (feature-parity-checklist). |
| R3 | Background tasks / reminders differ on iOS | Medium | `BGTaskScheduler` + `UNUserNotificationCenter`; accept best-effort timing vs Android alarms |
| R4 | CI cannot sign → install path differs | Low | Unsigned IPA + iLoader signing on-device (INSTALLING-IPA.md); CI builds with signing disabled |
| R5 | MathJax via CDN needs network | Low | Bundle MathJax locally (DL-008) |
| R6 | Prompt-caching beta header / API changes | Low | Header + model ids centralized; covered by `ClaudeAPIClientTests`; easy to bump |
| R7 | Accidental writes to the read-only Android source | High (process) | Never run mutating git/format/build in the Android dir; re-verify `git status` after each milestone |
| R8 | Secrets leakage (API key in logs/CI/git) | High | Keychain storage; `.gitignore` for secrets; no key printing; secret-scan check (TESTING.md / pre-commit) |
| R9 | WKWebView injection from AI-generated or imported HTML | Medium | Restrict allowed tags (prompt rules), no JS in card WebView, sanitize media paths |
| R10 | iOS 16 API drift / device coverage | Low | Conservative deployment target (DL-004) |
| R11 | Large scope vs single session | Process | Milestoned roadmap; canonical `progress.md`; stub gateway lets M1 ship independently |
