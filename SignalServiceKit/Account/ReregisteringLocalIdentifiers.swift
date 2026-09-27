//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct ReregisteringLocalIdentifiers {
    public let phoneNumber: String
    public let aci: Aci?
}
