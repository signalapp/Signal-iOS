//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/TSInfoMessage.h>

NS_ASSUME_NONNULL_BEGIN

// This is a deprecated class, we're keeping it around to avoid YapDB serialization errors
// TODO - remove this class, clean up existing instances, ensure any missed ones don't explode (UnknownDBObject)
__attribute__((deprecated)) @interface OWSAddToContactsOfferMessage : TSInfoMessage

// --- CODE GENERATION MARKER

// --- CODE GENERATION MARKER

@end

NS_ASSUME_NONNULL_END
