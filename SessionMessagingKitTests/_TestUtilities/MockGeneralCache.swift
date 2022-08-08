// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

@testable import SessionMessagingKit

class MockGeneralCache: Mock<GeneralCacheType>, GeneralCacheType {
    var encodedPublicKey: String? {
        get { return accept() as? String }
        set { accept(args: [newValue]) }
    }
}
