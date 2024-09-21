//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Distinguishes which kind of identity we're referring to.
///
/// The ACI ("account identifier") represents the user in question,
/// while the PNI ("phone number identifier") represents the user's phone number (e164).
///
/// And yes, that means the full enumerator names mean "account identifier identity" and
/// "phone number identifier identity".
@objc
public enum OWSIdentity: UInt8 {
    case aci
    case pni
}
