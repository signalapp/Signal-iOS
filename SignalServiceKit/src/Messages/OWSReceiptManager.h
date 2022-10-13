//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/BaseModel.h>

NS_ASSUME_NONNULL_BEGIN

@class GRDBWriteTransaction;
@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;
@class SSKProtoSyncMessageRead;
@class SSKProtoSyncMessageViewed;
@class SignalServiceAddress;
@class StoryMessage;
@class TSIncomingMessage;
@class TSMessage;
@class TSOutgoingMessage;
@class TSThread;

typedef NS_ENUM(NSInteger, OWSReceiptCircumstance) {
    OWSReceiptCircumstanceOnLinkedDevice,
    OWSReceiptCircumstanceOnLinkedDeviceWhilePendingMessageRequest,
    OWSReceiptCircumstanceOnThisDevice,
    OWSReceiptCircumstanceOnThisDeviceWhilePendingMessageRequest
};

extern NSString *const kIncomingMessageMarkedAsReadNotification;

#pragma mark -

// There are four kinds of read receipts:
//
// * Read receipts that this client sends to linked
//   devices to inform them that a message has been read.
// * Read receipts that this client receives from linked
//   devices that inform this client that a message has been read.
//    * These read receipts are saved so that they can be applied
//      if they arrive before the corresponding message.
// * Read receipts that this client sends to other users
//   to inform them that a message has been read.
// * Read receipts that this client receives from other users
//   that inform this client that a message has been read.
//    * These read receipts are saved so that they can be applied
//      if they arrive before the corresponding message.
//
// This manager is responsible for handling and emitting all four kinds.
@interface OWSReceiptManager : NSObject

+ (SDSKeyValueStore *)keyValueStore;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

#pragma mark - Sender/Recipient Read Receipts

// This method should be called when we receive a read receipt
// from a user to whom we have sent a message.
//
// This method can be called from any thread.

/// Returns an array of timestamps that had missing messages
- (NSArray<NSNumber *> *)processReadReceiptsFromRecipient:(SignalServiceAddress *)address
                                        recipientDeviceId:(uint32_t)deviceId
                                           sentTimestamps:(NSArray<NSNumber *> *)sentTimestamps
                                            readTimestamp:(uint64_t)readTimestamp
                                              transaction:(SDSAnyWriteTransaction *)transaction;

- (NSArray<NSNumber *> *)processViewedReceiptsFromRecipient:(SignalServiceAddress *)address
                                          recipientDeviceId:(uint32_t)deviceId
                                             sentTimestamps:(NSArray<NSNumber *> *)sentTimestamps
                                            viewedTimestamp:(uint64_t)viewedTimestamp
                                                transaction:(SDSAnyWriteTransaction *)transaction;

#pragma mark - Linked Device Read Receipts

/// Returns an array of receipts that had missing messages.
- (NSArray<SSKProtoSyncMessageRead *> *)processReadReceiptsFromLinkedDevice:
                                            (NSArray<SSKProtoSyncMessageRead *> *)readReceiptProtos
                                                              readTimestamp:(uint64_t)readTimestamp
                                                                transaction:(SDSAnyWriteTransaction *)transaction;

/// Returns an array of receipts that had missing messages.
- (NSArray<SSKProtoSyncMessageViewed *> *)processViewedReceiptsFromLinkedDevice:
                                              (NSArray<SSKProtoSyncMessageViewed *> *)viewedReceiptProtos
                                                                viewedTimestamp:(uint64_t)viewedTimestamp
                                                                    transaction:(SDSAnyWriteTransaction *)transaction;


- (void)markAsViewedOnLinkedDevice:(TSMessage *)message
                            thread:(TSThread *)thread
                   viewedTimestamp:(uint64_t)viewedTimestamp
                       transaction:(SDSAnyWriteTransaction *)transaction;

#pragma mark - Locally Read

// This method can be called from any thread.
- (void)messageWasRead:(TSIncomingMessage *)message
                thread:(TSThread *)thread
          circumstance:(OWSReceiptCircumstance)circumstance
           transaction:(SDSAnyWriteTransaction *)transaction;

- (void)messageWasViewed:(TSIncomingMessage *)message
                  thread:(TSThread *)thread
            circumstance:(OWSReceiptCircumstance)circumstance
             transaction:(SDSAnyWriteTransaction *)transaction;

- (void)storyWasViewed:(StoryMessage *)storyMessage
          circumstance:(OWSReceiptCircumstance)circumstance
           transaction:(SDSAnyWriteTransaction *)transaction;

- (void)incomingGiftWasRedeemed:(TSIncomingMessage *)incomingMessage transaction:(SDSAnyWriteTransaction *)transaction;
- (void)outgoingGiftWasOpened:(TSOutgoingMessage *)outgoingMessage transaction:(SDSAnyWriteTransaction *)transaction;

#pragma mark - Settings

- (void)prepareCachedValues;

- (BOOL)areReadReceiptsEnabled;

- (void)setAreReadReceiptsEnabledWithSneakyTransactionAndSyncConfiguration:(BOOL)value;

- (void)setAreReadReceiptsEnabled:(BOOL)value transaction:(SDSAnyWriteTransaction *)transaction;


@end

@protocol PendingReceiptRecorder

- (void)recordPendingReadReceiptForMessage:(TSIncomingMessage *)message
                                    thread:(TSThread *)thread
                               transaction:(GRDBWriteTransaction *)transaction;

- (void)recordPendingViewedReceiptForMessage:(TSIncomingMessage *)message
                                      thread:(TSThread *)thread
                                 transaction:(GRDBWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
