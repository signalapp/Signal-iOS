//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosEnvelope;
@class OWSSignalServiceProtosReceiptMessage;
@class TSIncomingMessage;
@class TSOutgoingMessage;
@class TSThread;
@class YapDatabaseReadWriteTransaction;

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
// TODO: Merge OWSReadReceiptsProcessor into this class.
@interface OWSReadReceiptManager : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)sharedManager;

// This method should be called when we receive a read receipt
// from a user to whom we have sent a message.
//
// This method can be called from any thread.
- (void)processReadReceiptsFromRecipient:(OWSSignalServiceProtosReceiptMessage *)receiptMessage
                                envelope:(OWSSignalServiceProtosEnvelope *)envelope;

- (void)updateOutgoingMessageFromLinkedDevice:(TSOutgoingMessage *)message
                                  transaction:(YapDatabaseReadWriteTransaction *)transaction;

// This method cues this manager:
//
// * ...to inform the sender that this message was read (if read receipts
//      are enabled).
// * ...to inform the local user's other devices that this message was read.
//
// Both types of messages are deduplicated.
//
// This method can be called from any thread.
- (void)messageWasReadLocally:(TSIncomingMessage *)message;

- (void)markAsReadLocallyBeforeTimestamp:(uint64_t)timestamp thread:(TSThread *)thread;

#pragma mark - Settings

- (BOOL)areReadReceiptsEnabled;
- (void)setAreReadReceiptsEnabled:(BOOL)value;

@end

NS_ASSUME_NONNULL_END
