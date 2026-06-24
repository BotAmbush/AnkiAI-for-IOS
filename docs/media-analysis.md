# Media Analysis

## Anki media (M2, backend)
Images/audio referenced by cards live in a `collection.media/` folder with a media DB tracked
by the backend (`libanki/.../Media.kt` wrapper). Rendering resolves `<img src>` / `[sound:…]`
against that folder. iOS plan: reuse backend media handling; serve media to `CardWebView` via a
local base URL / `WKURLSchemeHandler` (M2). Security: sanitize paths, prevent traversal, never
execute remote scripts in the card WebView (CLAUDE.md security requirement).

## AI creator attachments (fork-specific, M1 tail/M3)
The Android creator accepts photos and PDFs, scales them (≤1568px), JPEG-compresses, base64-encodes,
and sends them as image content blocks to Claude (Sonnet). PDFs are rasterized per page via
`PdfRenderer`.

iOS port:
- `ClaudeAPIClient.chatWithImages` + `ChatTurnWithImage`/`ImagePayload` already support image blocks (✅, tested).
- Pending: SwiftUI attachment picker (`PhotosPicker` / camera), image downscale/JPEG encode, and a
  PDF→image step using **PDFKit/`CGPDFDocument`** (the iOS analog of `PdfRenderer`).

## Status
- AI image transport: ✅ (client/model).
- Attachment capture UI + PDF rasterization: ☐.
- Anki media store + WebView serving: ☐ (M2).
