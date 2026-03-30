//
//  CloudSharingSheet.swift
//  TheGomsons
//

import SwiftUI
import UIKit

/// Presents the system share sheet configured for CloudKit family sharing (iOS 17+ API path).
struct FamilyShareActivityRepresentable: UIViewControllerRepresentable {
    var onDismiss: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = CloudDataManager.shared.makeFamilyShareActivityViewController()
        vc.completionWithItemsHandler = { _, _, _, _ in
            onDismiss?()
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        if let popover = uiViewController.popoverPresentationController {
            popover.sourceView = uiViewController.view
            popover.sourceRect = CGRect(
                x: uiViewController.view.bounds.midX,
                y: uiViewController.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
    }
}
