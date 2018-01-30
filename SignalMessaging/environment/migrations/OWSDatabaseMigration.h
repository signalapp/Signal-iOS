//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSYapDatabaseObject.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^OWSDatabaseMigrationCompletion)(void);

@class TSStorageManager;

@interface OWSDatabaseMigration : TSYapDatabaseObject

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager;

@property (nonatomic, readonly) TSStorageManager *storageManager;

// Prefer nonblocking (async) migrations by overriding `runUpWithTransaction:` in a subclass.
// Blocking migrations running too long will crash the app, effectively bricking install
// because the user will never get past it.
// If you must write a launch-blocking migration, override runUp.
- (void)runUpWithCompletion:(OWSDatabaseMigrationCompletion)completion;

@end

NS_ASSUME_NONNULL_END
