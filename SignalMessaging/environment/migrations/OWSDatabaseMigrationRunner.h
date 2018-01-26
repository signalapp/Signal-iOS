//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
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
 * On new installations, no need to migrate anything.
 */
- (void)assumeAllExistingMigrationsRun;

@end

NS_ASSUME_NONNULL_END
