//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SwiftUI

public struct ScrollableContentPinnedFooterView<
    ScrollableContent: View,
    PinnedFooter: View
>: View {
    private let scrollableContent: ScrollableContent
    private let pinnedFooter: PinnedFooter

    public init(
        @ViewBuilder scrollableContent: () -> ScrollableContent,
        @ViewBuilder pinnedFooter: () -> PinnedFooter,
    ) {
        self.scrollableContent = scrollableContent()
        self.pinnedFooter = pinnedFooter()
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                scrollableContent
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
