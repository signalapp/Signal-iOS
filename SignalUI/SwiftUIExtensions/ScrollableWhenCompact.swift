//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SwiftUI

public struct ScrollableWhenCompact<Content: View>: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        if verticalSizeClass == .compact {
            ScrollView {
                content
            }
            .scrollBounceBehaviorIfAvailable(.basedOnSize)
        } else {
            content
        }
    }
}
