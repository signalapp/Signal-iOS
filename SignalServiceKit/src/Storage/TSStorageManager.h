//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSStorageManager : OWSStorage

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

- (YapDatabaseConnection *)dbReadConnection;
- (YapDatabaseConnection *)dbReadWriteConnection;
+ (YapDatabaseConnection *)dbReadConnection;
+ (YapDatabaseConnection *)dbReadWriteConnection;

+ (void)migrateToSharedData;

@end

NS_ASSUME_NONNULL_END
