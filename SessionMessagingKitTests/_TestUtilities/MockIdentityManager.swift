// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

@testable import SessionMessagingKit

class MockIdentityManager: Mock<IdentityManagerProtocol>, IdentityManagerProtocol {
    func identityKeyPair() -> ECKeyPair? { return accept() as? ECKeyPair }
}
