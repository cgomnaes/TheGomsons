//
//  LandingPageView.swift
//  TheGomsons
//

import SwiftUI
import UIKit

struct LandingPageView: View {
    @ObservedObject var ackStore: LandingAckStore
    var onSelectSection: (AppRootTab) -> Void

    /// Springfield-flavored one-liners for the subtitle (original + nod-to-classic tone).
    private static let landingQuotes: [String] = [
        "D'oh! — tap a tile before I mess this up.",
        "Mmm… family data.",
        "Don't have a cow, man — just pick a section.",
        "¡Ay, caramba! So many choices!",
        "Everything's coming up Gomsons!",
        "Excellent. *tents fingers*",
        "What are we doing today? Besides being awesome.",
        "Okily dokily — choose a tab, neighborino!",
        "Hi-diddly-ho! The hub awaits.",
        "Why you little— …shortcut to joy? Tap below.",
        "I am so smart! S-M-A-R-T. (Tap to prove it.)",
        "Marge, I'm confused! Oh — it's just the app. Got it.",
        "Purple is a fruit. These tiles are still useful.",
        "The Internet? On my phone? What a time to be alive!",
        "Dental plan! …Inventory needs labels. Same energy.",
        "I choo-choo-choose… a well-organized household.",
        "Smarch weather? Check the Hub calendar.",
        "More fun than a monorail pitch — pick Holidays!",
        "To organized homes — the cause of, and solution to, family peace.",
        "Kids, you tried your best. The lesson is: tap Dashboard.",
        "Stupid sexy spreadsheet vibes — open Properties.",
        "This log cabin of apps has five doors. Pick one!",
        "CloudKit: like a donut hole — empty until you share.",
        "Woo-hoo! Random quote achieved!",
        "Mmm… encrypted sprinkles. (iCloud, basically.)",
        "Let's go, team Gomson!",
        "Not a prank call — just your family hub.",
        "Release the hounds! …or gently open Inventory.",
        "That's unpossible! …unless you tap something.",
    ]

    @State private var subtitle: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                familyHeader

                VStack(spacing: 6) {
                    Text("The Gomsons")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(SimpsonsTheme.charcoal)
                    Text(subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SimpsonsTheme.charcoal.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14),
                    ],
                    spacing: 14
                ) {
                    ForEach(AppRootTab.allCases) { tab in
                        SectionTileButton(
                            tab: tab,
                            showHighlight: ackStore.hasHighlight(for: tab)
                        ) {
                            onSelectSection(tab)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .padding(.top, 16)
        }
        .background {
            ZStack {
                SimpsonsTheme.yellow
                    .ignoresSafeArea()
                VStack {
                    Spacer()
                    Wave()
                        .fill(SimpsonsTheme.skyBlue.opacity(0.28))
                        .frame(height: 160)
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .onAppear {
            subtitle = Self.landingQuotes.randomElement() ?? "Welcome home!"
        }
    }

    // MARK: - Family header

    private var familyHeader: some View {
        ZStack {
            if let ui = UIImage(named: "FamilyPhoto") {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                familyPlaceholderArt
            }
        }
        .frame(height: 140)
        .frame(maxWidth: 400)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(SimpsonsTheme.charcoal.opacity(0.18), lineWidth: 3)
        }
        .shadow(color: SimpsonsTheme.charcoal.opacity(0.14), radius: 12, y: 6)
        .padding(.horizontal, 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Family photo")
    }

    private var familyPlaceholderArt: some View {
        ZStack {
            LinearGradient(
                colors: [SimpsonsTheme.skyBlue, SimpsonsTheme.blue.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            HStack(spacing: -14) {
                ForEach(Array(["Pappa", "Mamma", "CC", "Herman"].enumerated()), id: \.offset) { i, name in
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [SimpsonsTheme.yellow, SimpsonsTheme.orange.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 54, height: 54)
                        .overlay {
                            Text(String(name.prefix(1)))
                                .font(.title2.weight(.black))
                                .foregroundStyle(SimpsonsTheme.charcoal)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(SimpsonsTheme.charcoal.opacity(0.25), lineWidth: 2.5)
                        }
                        .zIndex(Double(4 - i))
                }
            }
            .padding(.top, 6)
            VStack {
                Spacer()
                Text("Add FamilyPhoto to Assets")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(SimpsonsTheme.charcoal.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(SimpsonsTheme.white.opacity(0.55), in: Capsule())
                    .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Wave decoration

private struct Wave: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: 0, y: h * 0.38))
        p.addCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.15),
            control1: CGPoint(x: w * 0.12, y: h * 0.55),
            control2: CGPoint(x: w * 0.36, y: 0)
        )
        p.addCurve(
            to: CGPoint(x: w, y: h * 0.3),
            control1: CGPoint(x: w * 0.64, y: h * 0.32),
            control2: CGPoint(x: w * 0.85, y: h * 0.12)
        )
        p.addLine(to: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p
    }
}

// MARK: - Tile

private struct SectionTileButton: View {
    let tab: AppRootTab
    let showHighlight: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(tab.tileColor.opacity(0.18))
                            .frame(width: 56, height: 56)
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(tab.tileColor)
                    }

                    Text(tab.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SimpsonsTheme.charcoal)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .padding(.horizontal, 10)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(SimpsonsTheme.white)
                        .shadow(color: SimpsonsTheme.charcoal.opacity(0.08), radius: 10, y: 4)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(tab.tileColor.opacity(0.35), lineWidth: 2)
                }

                if showHighlight {
                    Text("NEW")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(SimpsonsTheme.orange, in: Capsule())
                        .offset(x: -8, y: 8)
                        .accessibilityLabel("New or updated")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(showHighlight ? "Has new or updated content." : "")
    }
}

#Preview {
    LandingPageView(
        ackStore: LandingAckStore(),
        onSelectSection: { _ in }
    )
}
