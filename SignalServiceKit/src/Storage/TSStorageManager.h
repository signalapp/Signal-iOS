//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"

NS_ASSUME_NONNULL_BEGIN

void runSyncRegistrationsForStorage(OWSStorage *storage);
void runAsyncRegistrationsForStorage(OWSStorage *storage);

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

+ (NSString *)legacyDatabaseFilePath;

@end

NS_ASSUME_NONNULL_END
