//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation

extension Progress {
    public var remainingUnitCount: Int64 { totalUnitCount - completedUnitCount }
}
