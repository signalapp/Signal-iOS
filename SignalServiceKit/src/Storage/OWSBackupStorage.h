//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//
#import "OWSPrimaryStorage.h"
#import "OWSStorage.h"

NS_ASSUME_NONNULL_BEGIN

// void runSyncRegistrationsForStorage(OWSStorage *storage);
// void runAsyncRegistrationsForStorage(OWSStorage *storage);

@interface OWSBackupStorage : OWSStorage

- (instancetype)init NS_UNAVAILABLE;

//+ (instancetype)sharedManager NS_SWIFT_NAME(shared());
//
- (YapDatabaseConnection *)dbConnection;
//
//+ (nullable NSError *)migrateToSharedData;
//
//+ (NSString *)databaseFilePath;
//
//+ (NSString *)legacyDatabaseFilePath;
//+ (NSString *)legacyDatabaseFilePath_SHM;
//+ (NSString *)legacyDatabaseFilePath_WAL;
//+ (NSString *)sharedDataDatabaseFilePath;
//+ (NSString *)sharedDataDatabaseFilePath_SHM;
//+ (NSString *)sharedDataDatabaseFilePath_WAL;

@end

NS_ASSUME_NONNULL_END
