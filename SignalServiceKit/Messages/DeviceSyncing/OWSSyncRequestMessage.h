//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSOutgoingSyncMessage.h>

NS_ASSUME_NONNULL_BEGIN

/// this is the actual type of ``requestType:`` down below but then swift cannot see the method
typedef NS_CLOSED_ENUM(int32_t, SSKProtoSyncMessageRequestType);

@interface OWSSyncRequestMessage : OWSOutgoingSyncMessage

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                        transaction:(DBReadTransaction *)transaction NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                      localThread:(TSContactThread *)localThread
                      transaction:(DBReadTransaction *)transaction NS_UNAVAILABLE;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                        requestType:(int32_t)requestType
                        transaction:(DBReadTransaction *)transaction NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
