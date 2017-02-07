//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@class YapDatabaseReadWriteTransaction;

/**
 * Some interactions track read/unread status.
 * e.g. incoming messages and call notifications
 */
@protocol OWSReadTracking <NSObject>

/**
 * Has the local user seen the interaction?
 */
@property (nonatomic, readonly, getter=wasRead) BOOL read;

/**
 * Call when the user viewed the message/call on this device. "locally" as opposed to being notified via a read receipt
 * sync message of a remote read.
 */
- (void)markAsReadLocally;
- (void)markAsReadLocallyWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

@property (nonatomic, readonly) NSString *uniqueThreadId;

@end
