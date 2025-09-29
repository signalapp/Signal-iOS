//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

/// Container for stateful objects needed to render spoilers.
final public class SpoilerRenderState {
    public let revealState: SpoilerRevealState
    public let animationManager: SpoilerAnimationManager

    public init() {
        self.revealState = SpoilerRevealState()
        self.animationManager = SpoilerAnimationManager()
    }
}
