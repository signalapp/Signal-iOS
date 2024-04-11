//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension FeatureBuild {
#if DEBUG
    static let current: FeatureBuild = .dev
#else
    static let current: FeatureBuild = .internal
#endif
}
