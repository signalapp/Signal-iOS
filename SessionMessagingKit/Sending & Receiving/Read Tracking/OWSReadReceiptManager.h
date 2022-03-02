//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSPrimaryStorage;
@class SNProtoSyncMessageRead;
@class TSIncomingMessage;
@class TSOutgoingMessage;
@class TSThread;
@class YapDatabaseReadTransaction;
@class YapDatabaseReadWriteTransaction;

extern NSString *const kIncomingMessageMarkedAsReadNotification;

@interface OWSReadReceiptManager : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;
+ (instancetype)sharedManager;

#pragma mark - Sender/Recipient Read Receipts

// This method should be called when we receive a read receipt
// from a user to whom we have sent a message.
//
// This method can be called from any thread.
- (void)processReadReceiptsFromRecipientId:(NSString *)recipientId
                            sentTimestamps:(NSArray<NSNumber *> *)sentTimestamps
                             readTimestamp:(uint64_t)readTimestamp;

#pragma mark - Locally Read

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

- (void)markAsReadLocallyBeforeSortId:(uint64_t)sortId thread:(TSThread *)thread trySendReadReceipt:(BOOL)trySendReadReceipt;

#pragma mark - Settings

- (void)prepareCachedValues;

- (BOOL)areReadReceiptsEnabled;
- (BOOL)areReadReceiptsEnabledWithTransaction:(YapDatabaseReadTransaction *)transaction;
- (void)setAreReadReceiptsEnabled:(BOOL)value;

@end

NS_ASSUME_NONNULL_END
