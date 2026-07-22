//
//  CameraImagePicker.swift
//  TheGomsons
//

import SwiftUI
import UIKit

struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.showsCameraControls = true
        let overlay = CaptureFramingOverlayView(frame: .zero)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        picker.cameraOverlayView = overlay
        picker.cameraViewTransform = .identity
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraImagePicker

        init(_ parent: CameraImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let raw = info[.originalImage] as? UIImage {
                parent.image = InventoryImageAnalyzer.prepareCapturedImage(raw)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Guides the user to center a household item before capture.
private final class CaptureFramingOverlayView: UIView {
    private let hintLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        hintLabel.text = String(localized: "stash.capture.hint")
        hintLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        hintLabel.textColor = .white
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 2
        hintLabel.layer.shadowColor = UIColor.black.cgColor
        hintLabel.layer.shadowOpacity = 0.85
        hintLabel.layer.shadowRadius = 4
        hintLabel.layer.shadowOffset = .zero
        addSubview(hintLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if let superview {
            frame = superview.bounds
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let frameRect = centerFrameRect(in: bounds)
        hintLabel.frame = CGRect(
            x: 24,
            y: max(frameRect.minY - 52, safeAreaInsets.top + 12),
            width: bounds.width - 48,
            height: 44
        )
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let frameRect = centerFrameRect(in: rect)
        let path = UIBezierPath(rect: rect)
        path.append(UIBezierPath(roundedRect: frameRect, cornerRadius: 16))
        path.usesEvenOddFillRule = true

        ctx.setFillColor(UIColor.black.withAlphaComponent(0.42).cgColor)
        path.fill()

        let stroke = UIBezierPath(roundedRect: frameRect, cornerRadius: 16)
        stroke.lineWidth = 2.5
        UIColor.white.withAlphaComponent(0.92).setStroke()
        stroke.stroke()

        drawCornerBrackets(in: frameRect)
    }

    private func centerFrameRect(in rect: CGRect) -> CGRect {
        let side = min(rect.width, rect.height) * 0.72
        return CGRect(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side
        )
    }

    private func drawCornerBrackets(in frame: CGRect) {
        let len: CGFloat = 22
        let line = UIBezierPath()
        line.lineWidth = 3
        UIColor.white.setStroke()

        // Top-left
        line.move(to: CGPoint(x: frame.minX, y: frame.minY + len))
        line.addLine(to: CGPoint(x: frame.minX, y: frame.minY))
        line.addLine(to: CGPoint(x: frame.minX + len, y: frame.minY))
        // Top-right
        line.move(to: CGPoint(x: frame.maxX - len, y: frame.minY))
        line.addLine(to: CGPoint(x: frame.maxX, y: frame.minY))
        line.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + len))
        // Bottom-left
        line.move(to: CGPoint(x: frame.minX, y: frame.maxY - len))
        line.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
        line.addLine(to: CGPoint(x: frame.minX + len, y: frame.maxY))
        // Bottom-right
        line.move(to: CGPoint(x: frame.maxX - len, y: frame.maxY))
        line.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
        line.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY - len))
        line.stroke()
    }
}
