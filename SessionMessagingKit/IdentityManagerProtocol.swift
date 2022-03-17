// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Curve25519Kit

public protocol IdentityManagerProtocol {
    func identityKeyPair() -> ECKeyPair?
}

extension OWSIdentityManager: IdentityManagerProtocol {}
