//
//  FamilyBradyBunchHeader.swift
//  TheGomsons
//
//  Brady Bunch–style portrait row from individual portrait illustrations (not group-photo crops).
//

import SwiftUI
import UIKit

enum FamilyHeaderDisplayMode {
    case groupPhoto
    case bradyBunch
}

/// One portrait slot in the landing Brady Bunch row (left → right).
struct FamilyPortraitSlot: Identifiable {
    let id: String
    let displayName: String
    let accessibilityName: String
    let assetName: String
    let tileColor: Color
    let tiltDegrees: Double
}

enum FamilyBradyBunchLayout {
    static let groupAssetName = "FamilyPhoto"

    /// Order: CC, Mamma, Pappa, Herman, Bluee.
    static let slots: [FamilyPortraitSlot] = [
        FamilyPortraitSlot(
            id: "cc",
            displayName: "CC",
            accessibilityName: "CC",
            assetName: "FamilyPortraitCC",
            tileColor: SimpsonsTheme.green,
            tiltDegrees: -1
        ),
        FamilyPortraitSlot(
            id: "mamma",
            displayName: "Mamma",
            accessibilityName: "Mamma",
            assetName: "FamilyPortraitMamma",
            tileColor: SimpsonsTheme.pink,
            tiltDegrees: 0.75
        ),
        FamilyPortraitSlot(
            id: "pappa",
            displayName: "Pappa",
            accessibilityName: "Pappa",
            assetName: "FamilyPortraitPappa",
            tileColor: SimpsonsTheme.skyBlue,
            tiltDegrees: -0.75
        ),
        FamilyPortraitSlot(
            id: "herman",
            displayName: "Herman",
            accessibilityName: "Herman",
            assetName: "FamilyPortraitHerman",
            tileColor: SimpsonsTheme.orange,
            tiltDegrees: 1
        ),
        FamilyPortraitSlot(
            id: "bluee",
            displayName: "Bluee",
            accessibilityName: "Bluee",
            assetName: "FamilyPortraitBluee",
            tileColor: SimpsonsTheme.purple,
            tiltDegrees: -1
        ),
    ]

    static func randomDisplayMode() -> FamilyHeaderDisplayMode {
        Bool.random() ? .bradyBunch : .groupPhoto
    }

    static func portraitAvailable() -> Bool {
        slots.allSatisfy { UIImage(named: $0.assetName) != nil }
    }
}

/// Five portrait boxes in a Brady Bunch–style row.
struct FamilyBradyBunchHeader: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(FamilyBradyBunchLayout.slots) { slot in
                BradyBunchPortraitBox(slot: slot)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            SimpsonsTheme.yellow.opacity(0.35),
                            SimpsonsTheme.skyBlue.opacity(0.22),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(SimpsonsTheme.charcoal.opacity(0.18), lineWidth: 3)
        }
        .shadow(color: SimpsonsTheme.charcoal.opacity(0.14), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "landing.family_portraits"))
    }
}

private struct BradyBunchPortraitBox: View {
    let slot: FamilyPortraitSlot

    private static let portraitAspect: CGFloat = 3 / 4

    var body: some View {
        VStack(spacing: 4) {
            portraitFrame
                .rotationEffect(.degrees(slot.tiltDegrees))

            Text(slot.displayName)
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(SimpsonsTheme.charcoal)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(slot.tileColor.opacity(0.92), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(SimpsonsTheme.charcoal.opacity(0.4), lineWidth: 1.5)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(slot.accessibilityName)
    }

    private var portraitFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(slot.tileColor)
                .shadow(color: SimpsonsTheme.charcoal.opacity(0.12), radius: 4, y: 2)

            portraitImage
                .padding(3)
        }
        .aspectRatio(Self.portraitAspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(SimpsonsTheme.charcoal, lineWidth: 2.5)
        }
    }

    @ViewBuilder
    private var portraitImage: some View {
        if let ui = UIImage(named: slot.assetName) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Image(systemName: slot.id == "bluee" ? "pawprint.fill" : "person.fill")
                .font(.title2)
                .foregroundStyle(SimpsonsTheme.charcoal.opacity(0.35))
        }
    }
}
