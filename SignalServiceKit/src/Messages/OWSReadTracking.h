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

@property (nonatomic, readonly) uint64_t timestampForSorting;
@property (nonatomic, readonly) NSString *uniqueThreadId;

- (BOOL)shouldAffectUnreadCounts;

/**
 * Used for *responding* to a remote read receipt or in response to user activity.
 */
- (void)markAsReadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
                  sendReadReceipt:(BOOL)sendReadReceipt
                 updateExpiration:(BOOL)updateExpiration;

@end
