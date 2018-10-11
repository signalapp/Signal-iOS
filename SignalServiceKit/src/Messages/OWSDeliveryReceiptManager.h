//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

//@class SSKProtoSyncMessageRead;
//@class TSIncomingMessage;
//@class TSOutgoingMessage;
//@class TSThread;
//@class YapDatabaseReadTransaction;
//@class YapDatabaseReadWriteTransaction;

@class OWSPrimaryStorage;
@class SSKProtoEnvelope;

// extern NSString *const kIncomingMessageMarkedAsReadNotification;

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
@interface OWSDeliveryReceiptManager : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;
+ (instancetype)sharedManager;

//#pragma mark - Sender/Recipient Read Receipts
//
//// This method should be called when we receive a read receipt
//// from a user to whom we have sent a message.
////
//// This method can be called from any thread.
//- (void)processDeliveryReceiptsFromRecipientId:(NSString *)recipientId
//                            sentTimestamps:(NSArray<NSNumber *> *)sentTimestamps
//                             readTimestamp:(uint64_t)readTimestamp;
//
//- (void)applyEarlyDeliveryReceiptsForOutgoingMessageFromLinkedDevice:(TSOutgoingMessage *)message
//                                                     transaction:(YapDatabaseReadWriteTransaction *)transaction;
//
//#pragma mark - Linked Device Read Receipts
//
//- (void)processDeliveryReceiptsFromLinkedDevice:(NSArray<SSKProtoSyncMessageRead *> *)DeliveryReceiptProtos
//                              readTimestamp:(uint64_t)readTimestamp
//                                transaction:(YapDatabaseReadWriteTransaction *)transaction;
//
//- (void)applyEarlyDeliveryReceiptsForIncomingMessage:(TSIncomingMessage *)message
//                                     transaction:(YapDatabaseReadWriteTransaction *)transaction;
//
//#pragma mark - Locally Read
//
//// This method cues this manager:
////
//// * ...to inform the sender that this message was read (if read receipts
////      are enabled).
//// * ...to inform the local user's other devices that this message was read.
////
//// Both types of messages are deduplicated.
////
//// This method can be called from any thread.
//- (void)messageWasReadLocally:(TSIncomingMessage *)message;
//
//- (void)markAsReadLocallyBeforeTimestamp:(uint64_t)timestamp thread:(TSThread *)thread;
//
//#pragma mark - Settings
//
//- (void)prepareCachedValues;
//
//- (BOOL)areDeliveryReceiptsEnabled;
//- (BOOL)areDeliveryReceiptsEnabledWithTransaction:(YapDatabaseReadTransaction *)transaction;
//- (void)setAreDeliveryReceiptsEnabled:(BOOL)value;

- (void)envelopeWasReceived:(SSKProtoEnvelope *)envelope;

@end

NS_ASSUME_NONNULL_END
