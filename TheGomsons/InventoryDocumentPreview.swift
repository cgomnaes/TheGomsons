//
//  InventoryDocumentPreview.swift
//  TheGomsons
//

import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Presents a temporary file via system Quick Look (PDF / image attachments).
struct InventoryDocumentPreviewSheet: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.fileURL = fileURL
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var fileURL: URL

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            fileURL as NSURL
        }
    }
}

enum InventoryDocumentFileHelper {
    /// Writes `data` to a unique temp file and returns the URL (caller should delete when done).
    static func writeTemporaryFile(data: Data, fileName: String) throws -> URL {
        let safe = fileName.isEmpty ? "document.pdf" : fileName
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let fileURL = url.appendingPathComponent(safe)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    static func contentType(for fileName: String, fallbackUTType: UTType?) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if let ut = UTType(filenameExtension: ext), let mime = ut.preferredMIMEType {
            return mime
        }
        if let mime = fallbackUTType?.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}
