//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

/// Distinguishes which kind of identity we're referring to.
///
/// The ACI ("account identifier") represents the user in question,
/// while the PNI ("phone number identifier") represents the user's phone number (e164).
///
/// And yes, that means the full enumerator names mean "account identifier identity" and
/// "phone number identifier identity".
typedef NS_CLOSED_ENUM(uint8_t, OWSIdentity) {
    OWSIdentityACI NS_SWIFT_NAME(aci),
    OWSIdentityPNI NS_SWIFT_NAME(pni)
};
