//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SwiftUI

// MARK: - Scroll Anchor

public struct ScrollAnchor: Equatable {
    public let topAnchor: Anchor<CGPoint>
    public let correction: CGFloat
}

public struct ScrollAnchorPreferenceKey: PreferenceKey {
    public typealias Value = [ScrollAnchor]

    public static var defaultValue: Value = []

    public static func reduce(value: inout Value, nextValue: () -> Value) {
        // We can't determine which one anchor we want without a GeometryProxy
        value.append(contentsOf: nextValue())
    }
}

public struct ProvideScrollAnchor: ViewModifier {
    var correction: CGFloat

    public func body(content: Content) -> some View {
        content
            .transformAnchorPreference(
                key: ScrollAnchorPreferenceKey.self,
                value: .top,
            ) { key, anchor in
                key.append(ScrollAnchor(topAnchor: anchor, correction: correction))
            }
    }
}

extension View {
    /// Apply to the top-most element in a scroll view
    /// (`ScrollView`, `List`, `Form`) to which ``readScrollOffset()``
    ///  has been applied to read the scroll offset.
    ///
    /// If this is applied to multiple subviews within a scroll view,
    /// the highest value is used in `readScrollOffset`.
    public func provideScrollAnchor(correction: CGFloat = 0) -> some View {
        self.modifier(ProvideScrollAnchor(correction: correction))
    }
}

// MARK: - ScrollOffset

public struct ScrollOffsetPreferenceKey: PreferenceKey {
    public static var defaultValue: CGFloat = -.infinity

    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public struct ScrollOffsetReader: ViewModifier {
    @State private var scrollOffset: CGFloat = 0

    public func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .onPreferenceChange(ScrollAnchorPreferenceKey.self) { anchors in
                    MainActor.assumeIsolated {
                        scrollOffset = anchors.map { scrollAnchor in
                            -(geometry[scrollAnchor.topAnchor].y + scrollAnchor.correction)
                        }.max() ?? 0
                    }
                }
        }
        .preference(key: ScrollOffsetPreferenceKey.self, value: scrollOffset)
    }
}

extension View {
    /// Apply to a scroll view (`ScrollView`, `List`, `Form`) to
    /// have it read scroll anchors in the content applied with
    /// ``provideScrollAnchor(correction:)`` and report the
    /// scroll view offset in ``ScrollOffsetPreferenceKey``.
    ///
    /// Note that if `provideScrollAnchor` is applied to multiple views in the
    /// scrolling content (as is done with ``SignalSection``), this will return
    /// the highest value read. If the content is
    /// loaded lazily (as is done with ``SignalList``), this will report the
    /// offset of the highest currently-rendered item, which may not reflect the
    /// total scroll distance.
    public func readScrollOffset() -> some View {
        self.modifier(ScrollOffsetReader())
    }
}

#Preview {
    NavigationView {
        SignalList {
            SignalSection {
                ForEach(0..<50) {
                    Text(verbatim: "Item \($0)")
                }
            }
        }
        .navigationTitle(Text(verbatim: "Title text"))
    }
    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { scrollOffset in
        print(scrollOffset)
    }
}
