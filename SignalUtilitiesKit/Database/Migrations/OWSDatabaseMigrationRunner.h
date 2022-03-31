//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef void (^OWSDatabaseMigrationCompletion)(BOOL success, BOOL requiresConfigurationSync);

@interface OWSDatabaseMigrationRunner : NSObject

/**
 * Run any outstanding version migrations.
 */
- (void)runAllOutstandingWithCompletion:(OWSDatabaseMigrationCompletion)completion;

/**
 * On new installations, no need to migrate anything.
 */
- (void)assumeAllExistingMigrationsRun;

@end

NS_ASSUME_NONNULL_END
