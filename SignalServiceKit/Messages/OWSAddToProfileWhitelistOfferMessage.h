//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/TSInfoMessage.h>

NS_ASSUME_NONNULL_BEGIN

// TODO: Remove this class, clean up existing instances, and ensure any
// missed ones don't explode (UnknownDBObject).

// This is a deprecated class. We're keeping it around to avoid YapDB
// serialization errors.
/* DEPRECATED */ @interface OWSAddToProfileWhitelistOfferMessage : TSInfoMessage

// --- CODE GENERATION MARKER

// --- CODE GENERATION MARKER

@end

NS_ASSUME_NONNULL_END
