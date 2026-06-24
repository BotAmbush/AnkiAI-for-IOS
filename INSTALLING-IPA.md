# Installing the unsigned IPA (iLoader)

CI produces **`AnkiAI-unsigned.ipa`** — a device build with **no Apple signature**. You sign and
install it on your own iPhone with iLoader (or a similar sideloading tool). This project never
handles your Apple ID, certificates, or provisioning profiles.

## 1. Get the IPA
GitHub → **Actions** → latest **iOS Build & Test** run → **Artifacts** → download
`AnkiAI-unsigned-ipa` → unzip to get `AnkiAI-unsigned.ipa`.

The IPA layout is the standard `Payload/AnkiAI.app/…` with a compiled `arm64` device executable.

## 2. Sign + install with iLoader
1. Install iLoader and connect your iPhone.
2. Open `AnkiAI-unsigned.ipa` in iLoader.
3. Sign with your own Apple ID / free personal team (iLoader handles signing on-device).
4. Install. Trust the developer profile if prompted: **Settings → General → VPN & Device
   Management → (your Apple ID) → Trust**.

## 3. First run
- Open **Settings → AI Assistant**, paste your Claude API key (stored in the Keychain), and tap
  **Test connection**.

## Notes
- Free personal teams expire after ~7 days — re-sign as needed.
- Core Anki features (decks/review/sync) appear after milestone 2; see `docs/known-issues.md`.
