//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"

NS_ASSUME_NONNULL_BEGIN

void runSyncRegistrationsForPrimaryStorage(OWSStorage *storage);
void runAsyncRegistrationsForPrimaryStorage(OWSStorage *storage);

// TODO: Rename to OWSPrimaryStorage?
@interface TSStorageManager : OWSStorage

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

- (YapDatabaseConnection *)dbReadConnection;
- (YapDatabaseConnection *)dbReadWriteConnection;
+ (YapDatabaseConnection *)dbReadConnection;
+ (YapDatabaseConnection *)dbReadWriteConnection;

+ (void)migrateToSharedData;

+ (NSString *)databaseFilePath;

@end

NS_ASSUME_NONNULL_END
