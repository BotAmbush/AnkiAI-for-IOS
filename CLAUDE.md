# AnkiAI Native iOS Migration

## Mission

Create a complete native iOS counterpart of the existing Android application.

Android source project:

C:\Users\Evyatar\AndroidStudioProjects\Anki-Android-AI

iOS destination project:

C:\AnkiAI-for-IOS

The objective is full functional parity with the actual Android application,
including the original AnkiDroid-derived functionality and every custom AI
feature added to this particular repository.

This is not a prototype, UI mockup, minimal example, or partial rewrite.

## Critical filesystem boundary

The Android source directory is strictly read-only.

Never:

- modify a file in the Android source
- create a file in the Android source
- run a formatter in the Android source
- update Gradle files or dependencies there
- commit, checkout, reset, clean, stash, move, rename, or delete anything there
- run a command that can alter generated files in the Android source

All implementation files, documentation, generated project files, scripts,
temporary migration tools, logs and build configuration must be created only
under:

C:\AnkiAI-for-IOS

At the beginning, record:

- Android repository HEAD
- Android git status
- all uncommitted and untracked source files relevant to the customized app

After every major milestone, verify that the Android repository status has not
changed.

## Product requirement

The iOS app must reproduce the complete functionality present in the inspected
Android repository, not merely the AI card-generation feature.

Determine functionality from the real source code, resources, manifests,
navigation definitions, tests, database code and build configuration. Do not
assume that standard AnkiDroid behavior is sufficient if this fork differs.

The parity review must include at least:

- collection handling
- decks and subdecks
- notes, cards and note types
- card templates and CSS
- front and back rendering
- HTML rendering
- MathJax rendering
- Hebrew and right-to-left behavior
- mixed RTL/LTR content
- cloze cards
- image, audio and other media
- card browser
- note and card editing
- review screen
- answer buttons
- undo
- bury and suspend
- flags and tags
- filtered decks
- custom study
- statistics
- scheduling
- FSRS behavior and configuration
- learning, review and relearning steps
- collection database compatibility
- imports and exports
- APKG and collection package behavior where present
- backups and restoration
- synchronization behavior
- AnkiWeb-related behavior if implemented
- settings and preferences
- notifications and reminders
- background tasks
- sharing and file opening
- accessibility
- dark mode
- localization
- every custom AI workflow
- Claude/API provider integration
- prompt management
- AI-generated card validation
- HTML produced by AI
- MathJax produced by AI
- error handling
- API-key storage
- any custom feature unique to this repository

## Native implementation requirement

Build a genuinely native iOS application.

Use:

- Swift
- SwiftUI for the primary UI
- UIKit where SwiftUI alone is unsuitable
- WKWebView where required for accurate HTML and MathJax rendering
- Swift concurrency with async/await
- native Apple storage and security APIs where appropriate
- Keychain for user credentials and API keys

Do not use:

- React Native
- Flutter
- Kotlin Multiplatform UI
- Compose Multiplatform
- an Android emulator wrapper
- a web application packaged as an iOS app
- a mechanical line-by-line Kotlin-to-Swift translation

Business logic may be ported conceptually, but the resulting design must be
appropriate for iOS.

## Architecture

Create clear boundaries between:

- user interface
- navigation
- domain models
- collection and scheduling logic
- persistence
- synchronization
- media handling
- import/export
- AI providers
- settings
- platform services

The architecture must allow unit testing without a physical iPhone.

Avoid giant views, global mutable state and direct API calls from SwiftUI views.

Before selecting an iOS dependency, verify:

- maintenance status
- license compatibility
- iOS support
- whether the same functionality is practical with native APIs

Record every third-party dependency and license.

Do not copy license headers away or conceal the origin of derived code.
Create THIRD_PARTY_NOTICES.md and LICENSES.md where required.

## Phase 1: exhaustive Android analysis

Inspect the complete Android project before making architectural assumptions.

Create:

docs/android-inventory.md
docs/screen-and-navigation-map.md
docs/feature-parity-checklist.md
docs/database-and-data-model.md
docs/scheduler-and-fsrs-analysis.md
docs/import-export-analysis.md
docs/sync-analysis.md
docs/media-analysis.md
docs/ai-feature-analysis.md
docs/ios-architecture.md
docs/migration-risks.md
docs/licensing-analysis.md
docs/implementation-roadmap.md
docs/decision-log.md
docs/progress.md
docs/known-issues.md

The inventory must map each Android feature to:

- Android source files
- data dependencies
- platform dependencies
- intended iOS implementation
- implementation status
- tests
- unresolved risks

Do not mark a feature complete merely because an iOS file with a similar name
exists.

## Phase 2: repository and build foundation

Initialize a separate Git repository in C:\AnkiAI-for-IOS if one does not
already exist.

Never initialize or alter Git state in the Android source.

Create:

- an appropriate Swift/Xcode .gitignore
- README.md
- CONTRIBUTING.md
- BUILDING.md
- TESTING.md
- INSTALLING-IPA.md
- SECURITY.md
- GitHub Actions workflow
- deterministic project-generation configuration where practical
- scripts for building and packaging
- a secret-scanning check

Prefer a deterministic project definition rather than repeatedly hand-editing
a fragile project.pbxproj file. A tool such as XcodeGen may be used if justified
and documented, but the macOS CI runner must be able to regenerate the project
reliably.

Use a normal Xcode project or workspace that Xcode can open later.

Target physical iPhone builds. Choose the lowest practical supported iOS
deployment version and record the decision. Do not silently require a newer
version for convenience.

## GitHub repository

Check whether GitHub CLI is installed and authenticated:

gh --version
gh auth status

If available, create a private repository named:

AnkiAI-for-IOS

Do not overwrite an existing remote repository.

If GitHub CLI is unavailable or unauthenticated, continue all local work and
document the exact command the user must run later.

Never commit:

- API keys
- Claude credentials
- Apple credentials
- certificates
- provisioning profiles
- personal tokens
- local Claude settings
- build output
- IPA files
- DerivedData
- xcuserdata

## GitHub Actions and Xcode compilation

The local computer is Windows and cannot perform the authoritative Xcode build.

Set up a manually triggered GitHub Actions workflow using:

workflow_dispatch

The macOS job must:

1. select a stable installed Xcode version
2. resolve all Swift package dependencies
3. generate the Xcode project if project generation is used
4. compile the app for a generic physical iPhone destination
5. compile without Apple signing credentials
6. run unit tests on an appropriate iOS Simulator
7. run UI tests where practical
8. collect complete build logs
9. collect test reports
10. collect dSYM files
11. package the device .app inside Payload/
12. produce AnkiAI-unsigned.ipa
13. upload the IPA and all diagnostic artifacts

The IPA will later be signed and installed separately with iLoader.

Do not request the user's Apple ID, certificate, provisioning profile or
developer-team identifier.

Set artifact retention to a modest duration to conserve storage.

## Phase 3: implementation sequence

Build in small, testable vertical slices.

Recommended order:

1. application lifecycle and navigation shell
2. domain models
3. collection opening and closing
4. persistence and migrations
5. deck list
6. card and note models
7. card browser
8. HTML, CSS and MathJax rendering
9. editor
10. review queue
11. review UI
12. scheduler behavior
13. FSRS
14. undo, bury, suspend, flags and tags
15. media
16. statistics
17. filtered decks and custom study
18. imports and exports
19. backups and restoration
20. synchronization
21. notifications and background behavior
22. all AI functionality
23. settings and remaining platform features
24. accessibility, localization and UI polish

For every slice:

- identify corresponding Android behavior
- write or update tests
- implement the iOS behavior
- update the parity checklist
- update progress.md
- commit the coherent change
- push when appropriate
- trigger GitHub Actions
- inspect the actual build result

Do not create dozens of empty placeholder files merely to make the project look
complete.

## Build-repair loop

After GitHub Actions is available:

1. push a coherent change
2. trigger the workflow
3. retrieve and inspect the full failure log
4. identify the root cause
5. fix the problem locally
6. commit the fix
7. push again
8. repeat until green

Never state that the application compiles unless an Xcode build on the macOS
runner actually succeeded.

Never state that an IPA is ready unless the workflow uploaded the IPA artifact.

If GitHub Actions cannot be triggered automatically, prepare the workflow and
tell the user exactly where to click, while continuing all work that does not
depend on the result.

## Testing requirements

Include tests for:

- database reads and writes
- migrations
- scheduling transitions
- FSRS calculations
- timezone and date-boundary behavior
- import/export round trips
- HTML sanitization and preservation
- MathJax content
- Hebrew and bidirectional text
- media path handling
- AI response parsing
- malformed AI responses
- network errors
- cancellation
- Keychain-backed credential handling
- feature parity regressions

Use fixtures derived legally from test data, not private user collections.

## Security and privacy

Do not embed API keys.

Provide a user-facing configuration flow for AI credentials.

Store secrets in Keychain.

Do not print secrets to logs or GitHub Actions output.

Review imported HTML and media handling for injection and path-traversal risks.

Do not upload the Android source or user data to unrelated services.

## Work discipline

Use small, descriptive Git commits.

Do not rewrite or squash history without being asked.

Do not use destructive Git commands.

Do not delete functioning code merely because a rewrite appears cleaner.

Maintain docs/progress.md as the canonical status ledger.

When context becomes large, update the documentation before compacting so a
new session can continue accurately.

If blocked on one feature, document the blocker and continue with independent
features.

Only ask the user when a decision:

- cannot be inferred from the existing app
- affects data compatibility
- risks data loss
- requires private credentials
- materially changes the product

Do not stop after producing the analysis documents. Continue into implementation
unless one of those genuine blockers occurs.

## Definition of done

The project is not complete until:

- the source Android repository remains unchanged
- every discovered Android feature has a parity status
- the iOS project is native Swift/SwiftUI
- the macOS GitHub Actions build is green
- automated tests pass
- a physical-device unsigned IPA is uploaded
- the IPA contains a valid compiled iPhone executable
- known limitations are documented honestly
- installation instructions for iLoader exist
- no secrets are present in Git history
- the final parity report distinguishes completed, partial and unsupported
  features

Begin by inspecting the source, capturing its baseline Git state and creating
the analysis documents. Then proceed through the implementation roadmap.
