//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SessionUtilitiesKit/TSYapDatabaseObject.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^OWSDatabaseMigrationCompletion)(BOOL success, BOOL requiresConfigurationSync);

@class OWSPrimaryStorage;

@interface OWSDatabaseMigration : TSYapDatabaseObject

@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;

// Prefer nonblocking (async) migrations by overriding `runUpWithTransaction:` in a subclass.
// Blocking migrations running too long will crash the app, effectively bricking install
// because the user will never get past it.
// If you must write a launch-blocking migration, override runUp.
- (void)runUpWithCompletion:(OWSDatabaseMigrationCompletion)completion;

@end

NS_ASSUME_NONNULL_END
