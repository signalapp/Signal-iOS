//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"
#import "TSStorageKeys.h"
#import "YapDatabaseConnection+OWS.h"

@class ECKeyPair;
@class PreKeyRecord;
@class SignedPreKeyRecord;

NS_ASSUME_NONNULL_BEGIN

@interface TSStorageManager : OWSStorage

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

/**
 * The safeBlockingMigrationsBlock block will
 * run any outstanding version migrations that are a) blocking and b) safe
 * to be run before the environment and storage is completely configured.
 *
 * Specifically, these migration should not depend on or affect the data
 * of any database view.
 */
- (void)setupDatabaseWithSafeBlockingMigrations:(void (^_Nonnull)(void))safeBlockingMigrationsBlock;

// TODO: Deprecate.
+ (YapDatabaseConnection *)dbReadConnection;
+ (YapDatabaseConnection *)dbReadWriteConnection;

+ (void)migrateToSharedData;

@end

NS_ASSUME_NONNULL_END
