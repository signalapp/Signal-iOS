//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSOutgoingSyncMessage.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSUInteger, OWSSyncMessageRequestResponseType) {
    OWSSyncMessageRequestResponseType_Accept,
    OWSSyncMessageRequestResponseType_Delete,
    OWSSyncMessageRequestResponseType_Block,
    OWSSyncMessageRequestResponseType_BlockAndDelete,
    OWSSyncMessageRequestResponseType_Spam,
    OWSSyncMessageRequestResponseType_BlockAndSpam
};

@interface OWSSyncMessageRequestResponseMessage : OWSOutgoingSyncMessage

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                        transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                      localThread:(TSContactThread *)localThread
                      transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;

- (instancetype)initWithLocalThread:(TSContactThread *)localThread
               messageRequestThread:(TSThread *)thread
                       responseType:(OWSSyncMessageRequestResponseType)responseType
                        transaction:(SDSAnyReadTransaction *)transaction NS_DESIGNATED_INITIALIZER
    NS_SWIFT_NAME(init(localThread:messageRequestThread:responseType:transaction:));
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
