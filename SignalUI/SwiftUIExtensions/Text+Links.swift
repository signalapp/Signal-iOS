//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SwiftUI
import SignalServiceKit

extension Text {
    /// Appends a tappable link with a custom action to the end of a `Text`.
    /// Includes a leading space.
    public func appendLink(
        _ title: String,
        useBold: Bool = false,
        tint: Color = Color.Signal.link,
        action: @escaping () -> Void,
    ) -> some View {
        // Placeholder URL is needed for the link, but it's thrown away in the OpenURLAction
        (self + Text(" [\(title)](https://support.signal.org/)").fontWeight(useBold ? .bold : nil))
            .tint(tint)
            .environment(\.openURL, OpenURLAction { _ in
                action()
                return .handled
            })
    }
}

#Preview {
    Text(verbatim: "Description text.")
        .appendLink(CommonStrings.learnMore) {
            print("Learn more")
        }
}
