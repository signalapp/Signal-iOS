//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <YapDatabase/YapDatabaseSecondaryIndex.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSDatabaseSecondaryIndexes : NSObject

+ (NSString *)registerTimeStampIndexExtensionName;

+ (YapDatabaseSecondaryIndex *)registerTimeStampIndex;

+ (void)enumerateMessagesWithTimestamp:(uint64_t)timestamp
                             withBlock:(void (^)(NSString *collection, NSString *key, BOOL *stop))block
                      usingTransaction:(YapDatabaseReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
