//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "StorageCoordinator.h"
#import "AppReadiness.h"
#import "YDBStorage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

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
    _nonGlobalDatabaseStorage = [[SDSDatabaseStorage alloc] initWithDatabaseFileUrl:databaseFileUrl delegate:self];

    [self configure];

    return self;
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
    switch (SSKFeatureFlags.storageMode) {
        case StorageModeGrdb:
            self.state = StorageCoordinatorStateGRDB;

            if (CurrentAppContext().isMainApp) {
                [AppReadiness
                    runNowOrWhenAppDidBecomeReadyAsync:^{
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                            [YDBStorage deleteYDBStorage];
                            [SSKPreferences clearLegacyDatabaseFlagsFrom:CurrentAppContext().appUserDefaults];
                        });
                    }
                                                 label:@"StorageCoordinator.configure"];
            }
            break;
        case StorageModeGrdbTests:
            self.state = StorageCoordinatorStateGRDBTests;
            break;
    }
}

- (BOOL)isDatabasePasswordAccessible
{
    return [GRDBDatabaseStorageAdapter isKeyAccessible];
}

@end

NS_ASSUME_NONNULL_END
