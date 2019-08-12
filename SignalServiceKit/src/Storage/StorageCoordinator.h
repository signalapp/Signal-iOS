//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SDSDatabaseStorage;

typedef NS_ENUM(NSUInteger, StorageCoordinatorState) {
    StorageCoordinatorStateYDB,
    StorageCoordinatorStateBeforeYDBToGRDBMigration,
    StorageCoordinatorStateDuringYDBToGRDBMigration,
    StorageCoordinatorStateGRDB,
    StorageCoordinatorStateYDBTests,
    StorageCoordinatorStateGRDBTests,
};
NSString *NSStringFromStorageCoordinatorState(StorageCoordinatorState value);

@interface StorageCoordinator : NSObject

@property (atomic, readonly) SDSDatabaseStorage *databaseStorage;

@property (atomic, readonly) StorageCoordinatorState state;

- (instancetype)init;

// These methods should only be called by the migration itself.
- (void)migrationYDBToGRDBWillBegin;
- (void)migrationYDBToGRDBDidComplete;

@end

NS_ASSUME_NONNULL_END
