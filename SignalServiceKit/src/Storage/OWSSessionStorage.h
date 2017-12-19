//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"

NS_ASSUME_NONNULL_BEGIN

// TODO: Migrate data from primary data store.
// TODO: Add "is migrated flag".
// TODO: Check "is migrated flag" before accessing session state.
// TODO: Close database in background.
// TODO: Use background task around transactions.
@interface OWSSessionStorage : OWSStorage

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

- (YapDatabaseConnection *)dbConnection;
+ (YapDatabaseConnection *)dbConnection;

+ (NSString *)databaseFilePath;

@end

NS_ASSUME_NONNULL_END
