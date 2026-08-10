//
//  CockerSpanielPeekOverlay.swift
//  TheGomsons
//
//  Full asset image (no bitmap cropping). Placed on edges using explicit frame alignment.
//  Slides off-screen when hidden (bottom/top/left/right) with rotation so the peek matches each edge.
//  When family news is available, shows a tappable speech bubble (“brings news”).
//

import SwiftUI
import UIKit

/// Max width/height for the on-screen dog (fraction of shorter screen side).
private enum PeekReveal {
    /// 40% smaller than the previous default (multiply linear dimensions by 0.6).
    private static let sizeScale: CGFloat = 0.6

    static func maxImageWidth(shortSide: CGFloat) -> CGFloat {
        max(120 * sizeScale, shortSide * 0.42 * sizeScale)
    }

    static func maxImageHeight(shortSide: CGFloat) -> CGFloat {
        max(140 * sizeScale, shortSide * 0.5 * sizeScale)
    }
}

/// Shared cadence so Bluee doesn’t reappear every few seconds or after every tab change.
private enum CockerPeekTiming {
    /// Minimum gap between peeks (survives section switches / view restarts).
    static let minimumGap: TimeInterval = 4 * 60
    /// Extra wait before the first peek after launch / returning with news.
    static let firstPeekDelayRange: ClosedRange<Double> = 45...90
    /// Wait after a peek finishes before the next one may start (on top of minimumGap).
    static let betweenPeeksRange: ClosedRange<Double> = 3 * 60...6 * 60
    /// How long the dog (and bubble) stay on screen.
    static let onScreenWithNewsRange: ClosedRange<Double> = 6...10
    static let onScreenIdleRange: ClosedRange<Double> = 2.5...4

    private static let lastPeekKey = "TheGomsons.CockerPeek.lastShownAt"

    static var secondsUntilAllowed: TimeInterval {
        let last = UserDefaults.standard.double(forKey: lastPeekKey)
        guard last > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince1970 - last
        return max(0, minimumGap - elapsed)
    }

    static func markPeekShown() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastPeekKey)
    }
}

struct CockerSpanielPeekOverlay: View {
    var isSuppressed: Bool
    var newsItems: [CockerNewsItem] = []
    var onOpenNews: ((CockerNewsItem) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isVisible = false
    @State private var corner: PeekCorner = .bottomTrailing
    @State private var vectorVariant = 0
    @State private var activeNews: CockerNewsItem?
    @State private var newsCursor = 0

    /// Single transparent PNG used for all peek appearances (see Assets: `CockerPeekDog`).
    private static let peekDogAssetName = "CockerPeekDog"

    private static var hasPeekDogAsset: Bool {
        UIImage(named: peekDogAssetName) != nil
    }

    private var showsNewsBubble: Bool {
        isVisible && activeNews != nil
    }

    var body: some View {
        GeometryReader { geo in
            let insetTop = geo.safeAreaInsets.top
            let insetBottom = geo.safeAreaInsets.bottom
            let insetH = geo.safeAreaInsets.leading
            let insetT = geo.safeAreaInsets.trailing
            let shortSide = min(geo.size.width, geo.size.height)
            let maxW = PeekReveal.maxImageWidth(shortSide: shortSide)
            let maxH = PeekReveal.maxImageHeight(shortSide: shortSide)
            let slideDistance = max(maxW, maxH) + 24
            let bubbleMaxWidth = min(220, max(160, geo.size.width * 0.42))

            if !isSuppressed {
                ZStack(alignment: corner.alignment) {
                    dogLayer(
                        maxW: maxW,
                        maxH: maxH,
                        slideDistance: slideDistance,
                        insetTop: insetTop,
                        insetBottom: insetBottom,
                        insetLeading: insetH,
                        insetTrailing: insetT
                    )

                    if showsNewsBubble, let news = activeNews {
                        newsBubble(news, maxWidth: bubbleMaxWidth)
                            .padding(corner.bubblePadding(
                                dogWidth: maxW,
                                dogHeight: maxH,
                                insetTop: insetTop,
                                insetBottom: insetBottom,
                                insetLeading: insetH,
                                insetTrailing: insetT
                            ))
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: corner.alignment)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(showsNewsBubble)
        .task(id: isSuppressed) {
            guard !isSuppressed else {
                isVisible = false
                activeNews = nil
                return
            }
            await peekLoop()
        }
        .onChange(of: newsItems) { _, newItems in
            if newItems.isEmpty {
                newsCursor = 0
            } else if newsCursor >= newItems.count {
                newsCursor %= newItems.count
            }
        }
    }

    private func dogLayer(
        maxW: CGFloat,
        maxH: CGFloat,
        slideDistance: CGFloat,
        insetTop: CGFloat,
        insetBottom: CGFloat,
        insetLeading: CGFloat,
        insetTrailing: CGFloat
    ) -> some View {
        let slide = corner.slideOffset(isVisible: isVisible, distance: slideDistance)
        let show = !reduceMotion || isVisible

        return Group {
            if Self.hasPeekDogAsset {
                Image(Self.peekDogAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: maxW, height: maxH, alignment: corner.imageFrameAlignment)
            } else {
                CartoonSpanielHeadOnly(variant: vectorVariant)
                    .frame(width: maxW, height: maxH, alignment: corner.imageFrameAlignment)
            }
        }
        .rotationEffect(.degrees(corner.rotationDegrees), anchor: corner.rotationAnchor)
        .scaleEffect(x: corner.flipX ? -1 : 1, y: 1, anchor: corner.flipScaleAnchor)
        .shadow(color: Color.black.opacity(0.2), radius: 5, y: 2)
        .offset(slide)
        .offset(corner.edgeNudge(
            insetTop: insetTop,
            insetBottom: insetBottom,
            insetLeading: insetLeading,
            insetTrailing: insetTrailing
        ))
        .opacity(show ? 1 : 0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func newsBubble(_ news: CockerNewsItem, maxWidth: CGFloat) -> some View {
        Button {
            CockerPeekTiming.markPeekShown()
            onOpenNews?(news)
        } label: {
            Text(news.message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SimpsonsTheme.charcoal)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(SimpsonsTheme.yellow)
                )
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(news.message)
        .accessibilityHint(String(localized: "cocker.news.open_hint"))
    }

    private func sleepUnlessCancelled(seconds: Double) async -> Bool {
        let ns = UInt64(max(seconds, 0) * 1_000_000_000)
        do {
            try await Task.sleep(nanoseconds: ns)
            return true
        } catch {
            return false
        }
    }

    @MainActor
    private func peekLoop() async {
        var isFirstCycle = true
        while !Task.isCancelled {
            // Honor shared cooldown first (tab changes used to restart the loop and peek again immediately).
            let cooldown = CockerPeekTiming.secondsUntilAllowed
            if cooldown > 0.5 {
                guard await sleepUnlessCancelled(seconds: cooldown) else { break }
            }

            let hidden: Double
            if isFirstCycle {
                hidden = Double.random(in: CockerPeekTiming.firstPeekDelayRange)
                isFirstCycle = false
            } else if newsItems.isEmpty {
                // Idle peeks (no news) stay rare.
                hidden = Double.random(in: 4 * 60...8 * 60)
            } else {
                hidden = Double.random(in: CockerPeekTiming.betweenPeeksRange)
            }
            guard await sleepUnlessCancelled(seconds: hidden) else { break }

            // Re-check cooldown after the wait (another overlay instance may have peeked).
            let remaining = CockerPeekTiming.secondsUntilAllowed
            if remaining > 0.5 {
                guard await sleepUnlessCancelled(seconds: remaining) else { break }
                continue
            }

            let nextCorner = PeekCorner.allCases.randomElement() ?? .bottomTrailing
            let nextVariant = Int.random(in: 0..<12)
            let nextNews: CockerNewsItem?
            if newsItems.isEmpty {
                nextNews = nil
            } else {
                nextNews = newsItems[newsCursor % newsItems.count]
                newsCursor += 1
            }

            let showAnimation: Animation = reduceMotion
                ? .easeOut(duration: 0.22)
                : .spring(response: 0.42, dampingFraction: 0.86, blendDuration: 0)

            withAnimation(showAnimation) {
                corner = nextCorner
                vectorVariant = nextVariant
                activeNews = nextNews
                isVisible = true
            }
            CockerPeekTiming.markPeekShown()

            let onScreen = nextNews == nil
                ? Double.random(in: CockerPeekTiming.onScreenIdleRange)
                : Double.random(in: CockerPeekTiming.onScreenWithNewsRange)
            guard await sleepUnlessCancelled(seconds: onScreen) else {
                withAnimation(.easeOut(duration: 0.2)) {
                    isVisible = false
                    activeNews = nil
                }
                break
            }

            let hideAnimation: Animation = reduceMotion
                ? .easeIn(duration: 0.18)
                : .spring(response: 0.38, dampingFraction: 0.92, blendDuration: 0)

            withAnimation(hideAnimation) {
                isVisible = false
                activeNews = nil
            }

            guard await sleepUnlessCancelled(seconds: 0.45) else { break }
        }
    }
}

// MARK: - Edge positions (corners + mid sides)

private enum PeekCorner: CaseIterable {
    case bottomLeading
    case bottomTrailing
    case topLeading
    case topTrailing
    case leadingCenter
    case trailingCenter

    var alignment: Alignment {
        switch self {
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .leadingCenter: .leading
        case .trailingCenter: .trailing
        }
    }

    var rotationDegrees: Double {
        switch self {
        case .bottomLeading, .bottomTrailing: 0
        case .topLeading, .topTrailing: 180
        case .leadingCenter: 90
        case .trailingCenter: 90
        }
    }

    var rotationAnchor: UnitPoint {
        switch self {
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .leadingCenter: .leading
        case .trailingCenter: .trailing
        }
    }

    var flipX: Bool {
        switch self {
        case .bottomTrailing, .topTrailing, .trailingCenter: true
        case .bottomLeading, .topLeading, .leadingCenter: false
        }
    }

    var flipScaleAnchor: UnitPoint {
        switch self {
        case .bottomTrailing: .bottomTrailing
        case .topTrailing: .topTrailing
        case .trailingCenter: .trailing
        case .bottomLeading, .topLeading, .leadingCenter: .center
        }
    }

    var imageFrameAlignment: Alignment {
        switch self {
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .leadingCenter: .leading
        case .trailingCenter: .trailing
        }
    }

    func slideOffset(isVisible: Bool, distance: CGFloat) -> CGSize {
        guard !isVisible else { return .zero }
        switch self {
        case .bottomLeading, .bottomTrailing:
            return CGSize(width: 0, height: distance)
        case .topLeading, .topTrailing:
            return CGSize(width: 0, height: -distance)
        case .leadingCenter:
            return CGSize(width: -distance, height: 0)
        case .trailingCenter:
            return CGSize(width: distance, height: 0)
        }
    }

    func edgeNudge(
        insetTop: CGFloat,
        insetBottom: CGFloat,
        insetLeading: CGFloat,
        insetTrailing: CGFloat
    ) -> CGSize {
        let e: CGFloat = 2
        switch self {
        case .bottomLeading:
            return CGSize(width: insetLeading + e, height: -insetBottom - e)
        case .bottomTrailing:
            return CGSize(width: -insetTrailing - e, height: -insetBottom - e)
        case .topLeading:
            return CGSize(width: insetLeading + e, height: insetTop + e)
        case .topTrailing:
            return CGSize(width: -insetTrailing - e, height: insetTop + e)
        case .leadingCenter:
            return CGSize(width: insetLeading + e, height: 0)
        case .trailingCenter:
            return CGSize(width: -insetTrailing - e, height: 0)
        }
    }

    /// Nudge the bubble inward from the dog so it sits on-screen and readable.
    func bubblePadding(
        dogWidth: CGFloat,
        dogHeight: CGFloat,
        insetTop: CGFloat,
        insetBottom: CGFloat,
        insetLeading: CGFloat,
        insetTrailing: CGFloat
    ) -> EdgeInsets {
        let gap: CGFloat = 10
        switch self {
        case .bottomLeading:
            return EdgeInsets(
                top: 0,
                leading: insetLeading + 8,
                bottom: insetBottom + dogHeight * 0.55 + gap,
                trailing: 16
            )
        case .bottomTrailing:
            return EdgeInsets(
                top: 0,
                leading: 16,
                bottom: insetBottom + dogHeight * 0.55 + gap,
                trailing: insetTrailing + 8
            )
        case .topLeading:
            return EdgeInsets(
                top: insetTop + dogHeight * 0.55 + gap,
                leading: insetLeading + 8,
                bottom: 0,
                trailing: 16
            )
        case .topTrailing:
            return EdgeInsets(
                top: insetTop + dogHeight * 0.55 + gap,
                leading: 16,
                bottom: 0,
                trailing: insetTrailing + 8
            )
        case .leadingCenter:
            return EdgeInsets(
                top: 0,
                leading: insetLeading + dogWidth * 0.55 + gap,
                bottom: 0,
                trailing: 16
            )
        case .trailingCenter:
            return EdgeInsets(
                top: 0,
                leading: 16,
                bottom: 0,
                trailing: insetTrailing + dogWidth * 0.55 + gap
            )
        }
    }
}

// MARK: - Vector fallback

private struct CartoonSpanielHeadOnly: View {
    let variant: Int

    private var earTilt: CGFloat {
        [0.0, 5.0, -6.0, 7.0, -4.0][variant % 5]
    }

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                longEar(side: -1, extraTilt: earTilt, s: s)
                    .offset(x: -0.37 * s, y: 0.03 * s)
                longEar(side: 1, extraTilt: -earTilt * 0.85, s: s)
                    .offset(x: 0.37 * s, y: 0.05 * s)

                Ellipse()
                    .fill(Color.black)
                    .frame(width: 0.78 * s, height: 0.72 * s)
                    .overlay {
                        Ellipse()
                            .strokeBorder(SimpsonsTheme.charcoal, lineWidth: max(1.5, s * 0.018))
                    }

                Capsule()
                    .fill(Color.white)
                    .frame(width: 0.24 * s, height: 0.48 * s)
                    .offset(y: -0.22 * s)
                    .overlay {
                        Capsule()
                            .strokeBorder(SimpsonsTheme.charcoal, lineWidth: max(1, s * 0.012))
                    }

                Ellipse()
                    .fill(Color.white)
                    .frame(width: 0.44 * s, height: 0.34 * s)
                    .offset(x: 0.09 * s, y: 0.16 * s)
                    .overlay {
                        Ellipse()
                            .strokeBorder(SimpsonsTheme.charcoal, lineWidth: max(1, s * 0.012))
                    }

                Group {
                    freckle(s: s).offset(x: -0.02 * s, y: 0.2 * s)
                    freckle(s: s).offset(x: 0.04 * s, y: 0.23 * s)
                    freckle(s: s).offset(x: 0.12 * s, y: 0.21 * s)
                    freckle(s: s).offset(x: 0.19 * s, y: 0.18 * s)
                }

                Ellipse()
                    .fill(Color.black)
                    .frame(width: 0.16 * s, height: 0.12 * s)
                    .offset(x: 0.24 * s, y: 0.14 * s)
                    .overlay {
                        Ellipse()
                            .strokeBorder(SimpsonsTheme.charcoal, lineWidth: max(1, s * 0.012))
                    }

                simpsonsEye(wink: variant % 7 == 1, s: s)
                    .offset(x: -0.12 * s, y: -0.12 * s)
                simpsonsEye(wink: variant % 7 == 2, s: s)
                    .offset(x: 0.1 * s, y: -0.14 * s)
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
        }
    }

    private func freckle(s: CGFloat) -> some View {
        Circle()
            .fill(Color.black)
            .frame(width: 0.035 * s, height: 0.035 * s)
    }

    private func longEar(side: CGFloat, extraTilt: CGFloat, s: CGFloat) -> some View {
        ZStack {
            Ellipse()
                .fill(Color.black)
                .frame(width: 0.3 * s, height: 0.62 * s)
                .overlay {
                    Ellipse()
                        .strokeBorder(SimpsonsTheme.charcoal, lineWidth: max(1.5, s * 0.016))
                }
            Ellipse()
                .fill(Color.white.opacity(0.2))
                .frame(width: 0.09 * s, height: 0.32 * s)
                .offset(x: side * 0.07 * s, y: 0.09 * s)
        }
        .rotationEffect(.degrees(Double(side * 18 + extraTilt)))
    }

    private func simpsonsEye(wink: Bool, s: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: (wink ? 0.19 : 0.22) * s, height: (wink ? 0.04 : 0.22) * s)
                .overlay {
                    Circle()
                        .strokeBorder(SimpsonsTheme.charcoal, lineWidth: max(1, s * 0.012))
                }
            if !wink {
                Circle()
                    .fill(Color.black)
                    .frame(width: 0.06 * s, height: 0.06 * s)
                    .offset(x: 0.02 * s, y: 0.02 * s)
            }
        }
    }
}
