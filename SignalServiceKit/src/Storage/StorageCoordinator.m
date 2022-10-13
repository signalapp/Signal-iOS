//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "StorageCoordinator.h"
#import "AppReadiness.h"
#import "YDBStorage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const StorageIsReadyNotification = @"StorageIsReadyNotification";

NSString *NSStringFromStorageCoordinatorState(StorageCoordinatorState value)
{
    switch (value) {
        case StorageCoordinatorStateGRDB:
            return @"StorageCoordinatorStateGRDB";
        case StorageCoordinatorStateGRDBTests:
            return @"StorageCoordinatorStateGRDBTests";
    }
}

NSString *NSStringForDataStore(DataStore value)
{
    switch (value) {
        case DataStoreGrdb:
            return @"DataStoreGrdb";
    }
}

#pragma mark -

@interface StorageCoordinator () <SDSDatabaseStorageDelegate>

@property (atomic) StorageCoordinatorState state;

@property (atomic) BOOL isStorageSetupComplete;

@end

#pragma mark -

@implementation StorageCoordinator

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    NSURL *databaseFileUrl = [GRDBDatabaseStorageAdapter databaseFileUrlWithDirectoryMode:DirectoryModePrimary];
    _databaseStorage = [[SDSDatabaseStorage alloc] initWithDatabaseFileUrl:databaseFileUrl delegate:self];

    [self configure];

    return self;
}

+ (BOOL)hasYdbFile
{
    BOOL hasYdbFile = YDBStorage.hasAnyYdbFile;

    if (hasYdbFile && !SSKPreferences.didEverUseYdb) {
        [SSKPreferences setDidEverUseYdb:YES];
    }

    return hasYdbFile;
}

+ (BOOL)hasGrdbFile
{
    NSString *grdbFilePath = SDSDatabaseStorage.grdbDatabaseFileUrl.path;
    return [OWSFileSystem fileOrFolderExistsAtPath:grdbFilePath];
}

+ (BOOL)hasInvalidDatabaseVersion
{
    if (SSKPreferences.hasUnknownGRDBSchema) {
        OWSFailDebug(@"Unknown GRDB schema.");
        return YES;
    }

    return NO;
}

- (StorageCoordinatorState)storageCoordinatorState
{
    return self.state;
}

- (void)configure
{
    OWSLogInfo(@"storageMode: %@", SSKFeatureFlags.storageModeDescription);

    // NOTE: By now, any move of YDB from the "app container"
    //       to the "shared container" should be complete, so
    //       we can ignore the "legacy" database files.
    BOOL hasYdbFile = self.class.hasYdbFile;
    OWSLogInfo(@"hasYdbFile: %d", hasYdbFile);

    BOOL hasGrdbFile = self.class.hasGrdbFile;
    OWSLogInfo(@"hasGrdbFile: %d", hasGrdbFile);

    OWSLogInfo(@"didEverUseYdb: %d", SSKPreferences.didEverUseYdb);

    switch (SSKFeatureFlags.storageMode) {
        case StorageModeGrdb:
            self.state = StorageCoordinatorStateGRDB;

            if (hasYdbFile) {
                [SSKPreferences setDidEverUseYdb:YES];
                [SSKPreferences setDidDropYdb:YES];
            }

            if (CurrentAppContext().isMainApp) {
                [AppReadiness
                    runNowOrWhenAppDidBecomeReadyAsync:^{
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                            ^{ [YDBStorage deleteYDBStorage]; });
                    }
                                                 label:@"StorageCoordinator.configure"];
            }
            break;
        case StorageModeGrdbTests:
            self.state = StorageCoordinatorStateGRDBTests;
            break;
    }

    OWSLogInfo(@"state: %@", NSStringFromStorageCoordinatorState(self.state));
}

- (BOOL)isDatabasePasswordAccessible
{
    return [GRDBDatabaseStorageAdapter isKeyAccessible];
}

- (void)markStorageSetupAsComplete
{
    self.isStorageSetupComplete = YES;

    [self postStorageIsReadyNotification];
}

- (void)postStorageIsReadyNotification
{
    OWSLogInfo(@"");
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[NSNotificationCenter defaultCenter] postNotificationNameAsync:StorageIsReadyNotification
                                                                 object:nil
                                                               userInfo:nil];
    });
}

- (BOOL)isStorageReady
{
    switch (self.state) {
        case StorageCoordinatorStateGRDB:
        case StorageCoordinatorStateGRDBTests:
            return self.isStorageSetupComplete;
    }
}

@end

NS_ASSUME_NONNULL_END
