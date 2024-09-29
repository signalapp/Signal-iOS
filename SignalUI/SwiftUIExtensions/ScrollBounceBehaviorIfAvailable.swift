//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SwiftUI

public struct ScrollBounceBehaviorIfAvailableModifier: ViewModifier {
    public enum Behavior {
        case automatic
        case always
        case basedOnSize

        @available(iOS 16.4, *)
        var asScrollBounceBehavior: ScrollBounceBehavior {
            switch self {
            case .automatic: .automatic
            case .always: .always
            case .basedOnSize: .basedOnSize
            }
        }
    }

    var behavior: Behavior

    public func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.scrollBounceBehavior(behavior.asScrollBounceBehavior)
        } else {
            content
        }
    }
}

extension View {
    public func scrollBounceBehaviorIfAvailable(_ behavior: ScrollBounceBehaviorIfAvailableModifier.Behavior) -> some View {
        modifier(ScrollBounceBehaviorIfAvailableModifier(behavior: behavior))
    }
}
