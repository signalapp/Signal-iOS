//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct OrchestratingSVRAuthCredential: Equatable {
    public let kbs: KBSAuthCredential
    public let svr2: SVR2AuthCredential

    public init(kbs: KBSAuthCredential, svr2: SVR2AuthCredential) {
        self.kbs = kbs
        self.svr2 = svr2
    }
}
