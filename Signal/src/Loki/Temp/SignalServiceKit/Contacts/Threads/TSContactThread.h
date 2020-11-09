//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const TSContactThreadPrefix;

typedef NS_ENUM(NSInteger, LKSessionResetStatus);

@interface TSContactThread : TSThread

// Loki: The current session reset status for this thread
@property (atomic) LKSessionResetStatus sessionResetStatus;
@property (atomic, readonly) NSArray<NSString *> *sessionRestoreDevices;

@property (nonatomic) BOOL hasDismissedOffers;

- (instancetype)initWithContactId:(NSString *)contactId;

+ (instancetype)getOrCreateThreadWithContactId:(NSString *)contactId NS_SWIFT_NAME(getOrCreateThread(contactId:));

+ (instancetype)getOrCreateThreadWithContactId:(NSString *)contactId
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction;

// Unlike getOrCreateThreadWithContactId, this will _NOT_ create a thread if one does not already exist.
+ (nullable instancetype)getThreadWithContactId:(NSString *)contactId transaction:(YapDatabaseReadTransaction *)transaction;

- (NSString *)contactIdentifier;

+ (NSString *)contactIdFromThreadId:(NSString *)threadId;

+ (NSString *)threadIdFromContactId:(NSString *)contactId;

// This method can be used to get the conversation color for a given
// recipient without using a read/write transaction to create a
// contact thread.
+ (NSString *)conversationColorNameForRecipientId:(NSString *)recipientId
                                      transaction:(YapDatabaseReadTransaction *)transaction;

#pragma mark - Loki Session Restore

- (void)addSessionRestoreDevice:(NSString *)hexEncodedPublicKey transaction:(YapDatabaseReadWriteTransaction *_Nullable)transaction;
- (void)removeAllSessionRestoreDevicesWithTransaction:(YapDatabaseReadWriteTransaction *_Nullable)transaction;

@end

NS_ASSUME_NONNULL_END
