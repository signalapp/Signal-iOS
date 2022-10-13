//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class SDSDatabaseStorage;

extern NSString *const StorageIsReadyNotification;

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

@property (atomic, readonly) SDSDatabaseStorage *databaseStorage;

@property (atomic, readonly) StorageCoordinatorState state;

@property (atomic, readonly) BOOL isStorageReady;

- (instancetype)init;

@property (class, nonatomic, readonly) BOOL hasGrdbFile;

@property (class, nonatomic, readonly) BOOL hasInvalidDatabaseVersion;

- (BOOL)isDatabasePasswordAccessible;

- (void)markStorageSetupAsComplete;

@end

NS_ASSUME_NONNULL_END
