//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSStorageManager;

@interface OWSDatabaseMigrationRunner : NSObject

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager;

@property (nonatomic, readonly) TSStorageManager *storageManager;

/**
 * Run any outstanding version migrations.
 */
- (void)runAllOutstanding;

/**
 * Run any outstanding version migrations that are a) blocking and b) safe
 * to be run before the environment and storage is completely configured.
 *
 * Specifically, these migrations should not depend on or affect the data
 * of any database view.
 */
- (void)runSafeBlockingMigrations;

/**
 * On new installations, no need to migrate anything.
 */
- (void)assumeAllExistingMigrationsRun;

@end

NS_ASSUME_NONNULL_END
