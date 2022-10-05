// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

@testable import SessionMessagingKit

class MockGeneralCache: Mock<GeneralCacheType>, GeneralCacheType {
    var encodedPublicKey: String? {
        get { return accept() as? String }
        set { accept(args: [newValue]) }
    }
    
    var recentReactionTimestamps: [Int64] {
        get { return (accept() as? [Int64] ?? []) }
        set { accept(args: [newValue]) }
    }
}
