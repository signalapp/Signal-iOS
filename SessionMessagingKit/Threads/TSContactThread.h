//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SessionMessagingKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const TSContactThreadPrefix;

@interface TSContactThread : TSThread

- (instancetype)initWithContactSessionID:(NSString *)contactSessionID;

+ (instancetype)getOrCreateThreadWithContactSessionID:(NSString *)contactSessionID NS_SWIFT_NAME(getOrCreateThread(contactSessionID:));

+ (instancetype)getOrCreateThreadWithContactSessionID:(NSString *)contactSessionID
                                          transaction:(YapDatabaseReadWriteTransaction *)transaction;

// Unlike getOrCreateThreadWithContactSessionID, this will _NOT_ create a thread if one does not already exist.
+ (nullable instancetype)getThreadWithContactSessionID:(NSString *)contactSessionID transaction:(YapDatabaseReadTransaction *)transaction;

- (NSString *)contactSessionID;

+ (NSString *)contactSessionIDFromThreadID:(NSString *)threadId;

+ (NSString *)threadIDFromContactSessionID:(NSString *)contactSessionID;

@end

NS_ASSUME_NONNULL_END
