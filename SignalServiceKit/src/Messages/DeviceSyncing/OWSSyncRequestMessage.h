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
- (instancetype)initWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                      transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread
                   requestType:(int32_t)requestType
                   transaction:(SDSAnyReadTransaction *)transaction NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
