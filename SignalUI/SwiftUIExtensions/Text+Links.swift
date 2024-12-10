//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SwiftUI
import SignalServiceKit

extension Text {
    /// Appends a tappable link with a custom action to the end of a `Text`.
    /// Includes a leading space.
    public func appendLink(_ title: String, action: @escaping () -> Void) -> some View {
        // Placeholder URL is needed for the link, but it's thrown away in the OpenURLAction
        (self + Text(" [\(title)](https://support.signal.org/)"))
            .tint(.Signal.accent)
            .environment(\.openURL, OpenURLAction { _ in
                action()
                return .handled
            })
    }

    public func appendLink(_ title: String, urlString: String) -> some View {
        (self + Text(" [\(title)](\(urlString))"))
            .tint(.Signal.accent)
    }
}

#Preview {
    Text(verbatim: "Description text.")
        .appendLink(CommonStrings.learnMore) {
            print("Learn more")
        }

    Text(verbatim: "Description text.")
        .appendLink(CommonStrings.learnMore, urlString: "https://support.signal.org/")
}
