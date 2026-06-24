# Security & Privacy

## Secrets
- The **Claude API key** is stored in the iOS **Keychain**
  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), never in `UserDefaults`, never in source,
  never committed. The Android fork used SharedPreferences; iOS upgrades this.
- AnkiWeb sync credentials (M2) will also go in the Keychain.
- No API keys are embedded in the app. Users supply their own (billed by Anthropic).
- Secrets are never printed to logs or CI output. `.gitignore` excludes keys, certs, profiles,
  `.env`, and local Claude settings. A secret-scan check lives in `tools/secret-scan.sh`.

## Data flow
AI conversations go **directly** from the device to Anthropic's API over HTTPS (`URLSession`). No
third-party server is involved. The Android source and any user collection are never uploaded
anywhere by this project.

## Card content rendering
Card HTML (including AI-generated and, at M2, imported HTML) renders in `WKWebView`. Mitigations:
- AI prompts restrict output to a small allowed tag set (`<div><span><b><br><hr><code>`) and forbid
  JavaScript, external CSS/fonts, and `<anki-mathjax>`.
- The card WebView does not execute page-supplied remote scripts beyond the math renderer (to be
  bundled locally — DL-008).
- Media paths (M2) are sanitized against traversal before being served to the WebView.

## Reporting
Open a private security advisory on the repository. Do not file public issues for vulnerabilities.
