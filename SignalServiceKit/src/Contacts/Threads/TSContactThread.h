//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

// Loki: Session reset state
typedef NS_ENUM(NSInteger, TSContactThreadSessionResetState) {
    // No ongoing session reset
    TSContactThreadSessionResetStateNone,
    // We initiated a session reset
    TSContactThreadSessionResetStateInitiated,
    // We received a session reset
    TSContactThreadSessionResetStateRequestReceived,
};

extern NSString *const TSContactThreadPrefix;

@interface TSContactThread : TSThread

// Loki: The current session reset state for this thread
@property (atomic) TSContactThreadSessionResetState sessionResetState;

@property (nonatomic) BOOL hasDismissedOffers;

+ (instancetype)getOrCreateThreadWithContactId:(NSString *)contactId NS_SWIFT_NAME(getOrCreateThread(contactId:));

+ (instancetype)getOrCreateThreadWithContactId:(NSString *)contactId
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction;

// Unlike getOrCreateThreadWithContactId, this will _NOT_ create a thread if one does not already exist.
+ (nullable instancetype)getThreadWithContactId:(NSString *)contactId transaction:(YapDatabaseReadTransaction *)transaction;

- (NSString *)contactIdentifier;

+ (NSString *)contactIdFromThreadId:(NSString *)threadId;

// This is only exposed for tests.
#ifdef DEBUG
+ (NSString *)threadIdFromContactId:(NSString *)contactId;
#endif

// This method can be used to get the conversation color for a given
// recipient without using a read/write transaction to create a
// contact thread.
+ (NSString *)conversationColorNameForRecipientId:(NSString *)recipientId
                                      transaction:(YapDatabaseReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
