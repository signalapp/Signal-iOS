//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class SDSDatabaseStorage;

typedef NS_CLOSED_ENUM(NSUInteger, DataStore) {
    DataStoreGrdb,
};
NSString *NSStringForDataStore(DataStore value);

typedef NS_CLOSED_ENUM(NSUInteger, StorageCoordinatorState) {
    StorageCoordinatorStateGRDB,
    StorageCoordinatorStateGRDBTests,
};
NSString *NSStringFromStorageCoordinatorState(StorageCoordinatorState value);

@interface StorageCoordinator : NSObject

/// Named this way to avoid colliding with `-[NSObject databaseStorage]`.
@property (atomic, readonly) SDSDatabaseStorage *nonGlobalDatabaseStorage;

@property (atomic, readonly) StorageCoordinatorState state;

- (instancetype)init;

@property (class, nonatomic, readonly) BOOL hasGrdbFile;

@property (class, nonatomic, readonly) BOOL hasInvalidDatabaseVersion;

- (BOOL)isDatabasePasswordAccessible;

@end

NS_ASSUME_NONNULL_END
