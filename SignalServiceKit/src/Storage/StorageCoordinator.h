//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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

// The data store that will be used once the app is ready.
// This data store may not be available before then.
@property (class, nonatomic, readonly) DataStore dataStoreForUI;

- (BOOL)isDatabasePasswordAccessible;

- (void)markStorageSetupAsComplete;

@end

NS_ASSUME_NONNULL_END
