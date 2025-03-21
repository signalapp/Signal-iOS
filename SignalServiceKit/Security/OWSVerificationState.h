//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(uint64_t, OWSVerificationState) {
    /// The user hasn't taken an explicit action on this identity key. It's
    /// trusted after `defaultUntrustedInterval`.
    OWSVerificationStateDefault = 0,

    /// The user has explicitly verified this identity key. It's trusted.
    OWSVerificationStateVerified = 1,

    /// The user has explicitly verified a previous identity key. This one will
    /// never be trusted based on elapsed time. The user must mark it as
    /// "verified" or "default acknowledged" to trust it.
    OWSVerificationStateNoLongerVerified = 2,

    /// The user hasn't verified this identity key, but they've explicitly
    /// chosen not to, so we don't need to check `defaultUntrustedInterval`.
    OWSVerificationStateDefaultAcknowledged = 3,
};

NS_ASSUME_NONNULL_END
