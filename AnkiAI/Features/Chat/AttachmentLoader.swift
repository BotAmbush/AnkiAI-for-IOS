import SwiftUI
import PhotosUI
import PDFKit
import UIKit

/// Converts picked photos / PDFs into `ImagePayload`s for the AI card creator
/// (M2.22). Images are normalized to JPEG; PDF pages are rasterized to images so
/// Claude can read scanned/printed material.
enum AttachmentLoader {
    /// Max PDF pages rasterized per import (keeps the request payload bounded).
    static let maxPDFPages = 6

    static func payload(from item: PhotosPickerItem) async -> ImagePayload? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return payload(fromImageData: data)
    }

    static func payload(fromImageData data: Data) -> ImagePayload? {
        guard let ui = UIImage(data: data), let jpeg = ui.jpegData(compressionQuality: 0.7) else { return nil }
        return ImagePayload(base64: jpeg.base64EncodedString(), mediaType: "image/jpeg")
    }

    static func pdfPayloads(from url: URL) -> [ImagePayload] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let doc = PDFDocument(url: url) else { return [] }
        var out: [ImagePayload] = []
        let count = min(doc.pageCount, maxPDFPages)
        for i in 0..<count {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.cgContext.translateBy(x: 0, y: size.height)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            if let jpeg = image.jpegData(compressionQuality: 0.6) {
                out.append(ImagePayload(base64: jpeg.base64EncodedString(), mediaType: "image/jpeg"))
            }
        }
        return out
    }
}
