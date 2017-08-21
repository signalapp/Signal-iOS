//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSContactThread : TSThread

@property (nonatomic) BOOL hasDismissedOffers;

+ (instancetype)getOrCreateThreadWithContactId:(NSString *)contactId NS_SWIFT_NAME(getOrCreateThread(contactId:));

+ (instancetype)getOrCreateThreadWithContactId:(NSString *)contactId
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (instancetype)getOrCreateThreadWithContactId:(NSString *)contactId
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction
                                         relay:(nullable NSString *)relay;

- (NSString *)contactIdentifier;

+ (NSString *)contactIdFromThreadId:(NSString *)threadId;

@end

NS_ASSUME_NONNULL_END
