//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SDSDatabaseStorage;

typedef NS_ENUM(NSUInteger, StorageCoordinatorState) {
    // GRDB TODO: Remove .ydb and ydbTests once we ship GRDB to production.
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

@property (class, nonatomic, readonly) BOOL hasYdbFile;
@property (class, nonatomic, readonly) BOOL hasGrdbFile;

- (BOOL)isDatabasePasswordAccessible;

#ifdef TESTABLE_BUILD
- (void)useGRDBForTests;
- (void)useYDBForTests;
#endif

@end

NS_ASSUME_NONNULL_END
