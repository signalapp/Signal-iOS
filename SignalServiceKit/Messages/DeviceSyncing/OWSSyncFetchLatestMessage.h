//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSOutgoingSyncMessage.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSUInteger, OWSSyncFetchType) {
    OWSSyncFetchType_Unknown,
    OWSSyncFetchType_LocalProfile,
    OWSSyncFetchType_StorageManifest,
    OWSSyncFetchType_SubscriptionStatus
};

@interface OWSSyncFetchLatestMessage : OWSOutgoingSyncMessage

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                        transaction:(DBReadTransaction *)transaction NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                      localThread:(TSContactThread *)localThread
                      transaction:(DBReadTransaction *)transaction NS_UNAVAILABLE;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                          fetchType:(OWSSyncFetchType)requestType
                        transaction:(DBReadTransaction *)transaction NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
