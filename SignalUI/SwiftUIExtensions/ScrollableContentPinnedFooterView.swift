//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SwiftUI

public struct ScrollableContentPinnedFooterView<
    ScrollableContent: View,
    PinnedFooter: View,
>: View {
    private let centersContentVertically: Bool
    private let scrollableContent: ScrollableContent
    private let pinnedFooter: PinnedFooter

    /// - Parameter centersContentVertically: Whether content shorter than the
    /// scroll viewport should be centered within it, rather than sitting at the
    /// top. Content taller than the viewport scrolls either way.
    public init(
        centersContentVertically: Bool = false,
        @ViewBuilder scrollableContent: () -> ScrollableContent,
        @ViewBuilder pinnedFooter: () -> PinnedFooter,
    ) {
        self.centersContentVertically = centersContentVertically
        self.scrollableContent = scrollableContent()
        self.pinnedFooter = pinnedFooter()
    }

    public var body: some View {
        if #available(iOS 26, *) {
            iOS26Body
        } else {
            iOS18Body
        }
    }

    @available(iOS 26, *)
    private var iOS26Body: some View {
        ScrollView {
            ZStack {
                if centersContentVertically {
                    // containerRelativeFrame gives this view a frame equal to
                    // its nearest container, thereby forcing the content to
                    // fill everything available.
                    //
                    // ZStack will center the scrollable content once its frame
                    // is set.
                    Color.clear
                        .containerRelativeFrame(.vertical)
                }

                scrollableContent
            }
        }
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 0) {
                pinnedFooter
            }
            .padding(.top, 24)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var iOS18Body: some View {
        VStack(spacing: 0) {
            // The footer is a sibling of the scroll view here, so wrapping the
            // scroll view measures the viewport directly.
            GeometryReader { scrollViewGeometry in
                ScrollView {
                    ZStack {
                        if centersContentVertically {
                            Color.clear
                                .frame(height: scrollViewGeometry.size.height)
                        }

                        scrollableContent
                    }
                }
                .scrollBounceBehaviorIfAvailable(.basedOnSize)
            }

            Spacer().frame(height: 24)

            pinnedFooter
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

// MARK: -

#if DEBUG

#Preview {
    ScrollableContentPinnedFooterView {
        Text(verbatim: String(repeating: "Lorem ipsum dolor sit amet ", count: 100))
            .padding(.horizontal, 24)
    } pinnedFooter: {
        Button {
            print("Continue pressed!")
        } label: {
            Text(verbatim: "Continue")
                .foregroundStyle(.white)
                .font(.headline)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .background(Color.Signal.ultramarine)
        .cornerRadius(12)
        .padding(.horizontal, 40)

        Spacer().frame(height: 16)

        Button {
            print("Not Now pressed!")
        } label: {
            Text(verbatim: "Not Now")
                .foregroundStyle(Color.Signal.ultramarine)
                .font(.headline)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }
}

#endif
