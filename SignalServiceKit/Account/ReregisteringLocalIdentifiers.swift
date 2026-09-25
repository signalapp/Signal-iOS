//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct ReregisteringLocalIdentifiers {
    public let phoneNumber: String?
    public let aci: Aci?

    init?(phoneNumber: String?, aci: Aci?) {
        guard phoneNumber != nil || aci != nil else {
            return nil
        }
        self.phoneNumber = phoneNumber
        self.aci = aci
    }
}
