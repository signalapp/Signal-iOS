//  Created by Michael Kirk on 9/28/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#include <SignalServiceKit/TSYapDatabaseObject.h>

NS_ASSUME_NONNULL_BEGIN

@class TSStorageManager;

@interface OWSDatabaseMigration : TSYapDatabaseObject

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager;

@property (nonatomic, readonly) TSStorageManager *storageManager;

/**
 * Run an asynchronous migration. Prefer this to the blocking variant whenever possible as the migration runner will
 * block launching, and potentially crash apps e.g. if a view is being populated.
 */
- (void)runUp;

/**
 * Run a synchronous migration.
 * TODO: there's currently no tooling in the migration runner to run BlockingMigrations, as we don't have any yet.
 * Try to avoid this whenever possible as the migration runner will block launching, and potentially crash apps
 * e.g. if a view is being populated.
 */
- (void)runUpWithBlockingMigration;

@end

NS_ASSUME_NONNULL_END
