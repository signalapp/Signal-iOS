//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SessionMessagingKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const TSContactThreadPrefix;

@interface TSContactThread : TSThread

@property (nonatomic, nullable) NSString *originalOpenGroupServer;
@property (nonatomic, nullable) NSString *originalOpenGroupPublicKey;

- (instancetype)initWithContactSessionID:(NSString *)contactSessionID;

+ (instancetype)getOrCreateThreadWithContactSessionID:(NSString *)contactSessionID NS_SWIFT_NAME(getOrCreateThread(contactSessionID:));
+ (instancetype)getOrCreateThreadWithContactSessionID:(NSString *)contactSessionID
                                      openGroupServer:(NSString *)openGroupServer
                                   openGroupPublicKey:(NSString *)openGroupPublicKey NS_SWIFT_NAME(getOrCreateThread(contactSessionID:openGroupServer:openGroupPublicKey:));

+ (instancetype)getOrCreateThreadWithContactSessionID:(NSString *)contactSessionID
                                          transaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (instancetype)getOrCreateThreadWithContactSessionID:(NSString *)contactSessionID
                                      openGroupServer:(NSString *)openGroupServer
                                   openGroupPublicKey:(NSString *)openGroupPublicKey
                                          transaction:(YapDatabaseReadWriteTransaction *)transaction;

// Unlike getOrCreateThreadWithContactSessionID, this will _NOT_ create a thread if one does not already exist.
+ (nullable instancetype)getThreadWithContactSessionID:(NSString *)contactSessionID transaction:(YapDatabaseReadTransaction *)transaction NS_SWIFT_NAME(fetch(for:using:));

- (NSString *)contactSessionID;

+ (NSString *)contactSessionIDFromThreadID:(NSString *)threadId;

+ (NSString *)threadIDFromContactSessionID:(NSString *)contactSessionID;

@end

NS_ASSUME_NONNULL_END
