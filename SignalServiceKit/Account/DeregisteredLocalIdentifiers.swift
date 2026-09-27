//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

/// Identifiers available when the user is "deregistered".
///
/// When "deregistered", the user was previously "registered", so some/all
/// of their former identifiers are available, and they are able to view
/// messages they've already sent/received.
///
/// When "unregistered", the user has never registered, so there's no
/// existing messages, no prior identifiers, and the user is immediately
/// shown the registration flow.
///
/// - SeeAlso: LocalIdentifiers
public struct DeregisteredLocalIdentifiers {
    public let aci: Aci?
    public let phoneNumber: String?
    public let pni: Pni?
}
