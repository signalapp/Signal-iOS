//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSOutgoingSyncMessage.h>

NS_ASSUME_NONNULL_BEGIN

@class SSKProtoSyncMessageSentBuilder;
@class TSOutgoingMessage;

/**
 * Notifies your other registered devices (if you have any) that you've sent a message.
 * This way the message you just sent can appear on all your devices.
 */
@interface OWSOutgoingSentMessageTranscript : OWSOutgoingSyncMessage

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                      transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;

- (instancetype)initWithLocalThread:(TSThread *)localThread
                      messageThread:(TSThread *)messageThread
                    outgoingMessage:(TSOutgoingMessage *)message
                  isRecipientUpdate:(BOOL)isRecipientUpdate
                        transaction:(SDSAnyReadTransaction *)transaction NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) TSOutgoingMessage *message;
@property (nonatomic, readonly) TSThread *messageThread;
@property (nonatomic, readonly) BOOL isRecipientUpdate;

- (BOOL)prepareDataSyncMessageContentWithSentBuilder:(SSKProtoSyncMessageSentBuilder *)sentBuilder
                                         transaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
