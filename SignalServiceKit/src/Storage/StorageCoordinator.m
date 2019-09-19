//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/StorageCoordinator.h>
#import <SignalServiceKit/NSNotificationCenter+OWS.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const StorageIsReadyNotification = @"StorageIsReadyNotification";

NSString *NSStringFromStorageCoordinatorState(StorageCoordinatorState value)
{
    switch (value) {
        case StorageCoordinatorStateYDB:
            return @"StorageCoordinatorStateYDB";
        case StorageCoordinatorStateBeforeYDBToGRDBMigration:
            return @"StorageCoordinatorStateBeforeYDBToGRDBMigration";
        case StorageCoordinatorStateDuringYDBToGRDBMigration:
            return @"StorageCoordinatorStateDuringYDBToGRDBMigration";
        case StorageCoordinatorStateGRDB:
            return @"StorageCoordinatorStateGRDB";
        case StorageCoordinatorStateYDBTests:
            return @"StorageCoordinatorStateYDBTests";
        case StorageCoordinatorStateGRDBTests:
            return @"StorageCoordinatorStateGRDBTests";
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

    _databaseStorage = [[SDSDatabaseStorage alloc] initWithDelegate:self];

    [self configure];

    return self;
}

+ (BOOL)hasYdbFile
{
    NSString *ydbFilePath = OWSPrimaryStorage.sharedDataDatabaseFilePath;
    return [OWSFileSystem fileOrFolderExistsAtPath:ydbFilePath];
}

+ (BOOL)hasGrdbFile
{
    NSString *grdbFilePath = SDSDatabaseStorage.grdbDatabaseFileUrl.path;
    return [OWSFileSystem fileOrFolderExistsAtPath:grdbFilePath];
}

- (StorageCoordinatorState)storageCoordinatorState
{
    return self.state;
}

- (BOOL)isMigrating
{
    StorageCoordinatorState state = self.state;
    return (state == StorageCoordinatorStateBeforeYDBToGRDBMigration
        || state == StorageCoordinatorStateDuringYDBToGRDBMigration);
}

- (void)configure
{
    OWSLogInfo(@"storageMode: %@", SSKFeatureFlags.storageModeDescription);

    // NOTE: By now, any move of YDB from the "app container"
    //       to the "shared container" should be complete, so
    //       we can ignore the "legacy" database files.
    BOOL hasYdbFile = self.class.hasYdbFile;
    OWSLogVerbose(@"hasYdbFile: %d", hasYdbFile);

    BOOL hasGrdbFile = self.class.hasGrdbFile;
    OWSLogVerbose(@"hasGrdbFile: %d", hasGrdbFile);

    switch (SSKFeatureFlags.storageMode) {
        case StorageModeYdb:
            self.state = StorageCoordinatorStateYDB;
            break;
        case StorageModeGrdb:
        case StorageModeGrdbThrowawayIfMigrating:
            if (hasYdbFile && ![SSKPreferences isYdbMigrated]) {
                self.state = StorageCoordinatorStateBeforeYDBToGRDBMigration;

                // We might want to delete any existing GRDB database
                // files here, since they represent an incomplete
                // previous migration and might cause problems.
                [self.databaseStorage deleteGrdbFiles];
            } else {
                self.state = StorageCoordinatorStateGRDB;

                [self removeYdbFiles];
            }
            break;
        case StorageModeYdbTests:
            self.state = StorageCoordinatorStateYDBTests;
            break;
        case StorageModeGrdbTests:
            self.state = StorageCoordinatorStateGRDBTests;
            break;
    }

    OWSLogInfo(@"state: %@", NSStringFromStorageCoordinatorState(self.state));
}

- (void)migrationYDBToGRDBWillBegin
{
    // These are crashing asserts.
    OWSAssert(self.state == StorageCoordinatorStateBeforeYDBToGRDBMigration);

    self.state = StorageCoordinatorStateDuringYDBToGRDBMigration;

    OWSLogInfo(@"state: %@", NSStringFromStorageCoordinatorState(self.state));
}

- (void)migrationYDBToGRDBDidComplete
{
    // These are crashing asserts.
    OWSAssert(self.state == StorageCoordinatorStateDuringYDBToGRDBMigration);

    self.state = StorageCoordinatorStateGRDB;

    OWSLogInfo(@"state: %@", NSStringFromStorageCoordinatorState(self.state));

    // Don't set this flag for "throwaway" migrations.
    if (SSKFeatureFlags.storageMode == StorageModeGrdb) {
        [SSKPreferences setIsYdbMigrated];
    }
}

- (BOOL)isDatabasePasswordAccessible
{
    if (self.databaseStorage.canLoadYdb) {
        if (![OWSPrimaryStorage isDatabasePasswordAccessible]) {
            return NO;
        }
    }
    if (self.databaseStorage.canLoadGrdb) {
        if (![GRDBDatabaseStorageAdapter isKeyAccessible]) {
            return NO;
        }
    }
    return YES;
}

#ifdef TESTABLE_BUILD
- (void)useGRDBForTests
{
    self.state = StorageCoordinatorStateGRDBTests;
}

- (void)useYDBForTests
{
    self.state = StorageCoordinatorStateYDBTests;
}
#endif

- (void)removeYdbFiles
{
    if (SSKFeatureFlags.preserveYdb) {
        // Don't clean up YDB..
        return;
    }
    if (SSKFeatureFlags.storageMode == StorageModeGrdbThrowawayIfMigrating) {
        // Don't clean up YDB; we're in throwaway mode.
        return;
    }

    [OWSStorage deleteDatabaseFiles];
    [OWSStorage deleteDBKeys];
}

- (void)storageSetupDidComplete
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
        case StorageCoordinatorStateYDB:
        case StorageCoordinatorStateYDBTests:
            return [OWSStorage isStorageReady] && self.isStorageSetupComplete;
        case StorageCoordinatorStateBeforeYDBToGRDBMigration:
        case StorageCoordinatorStateDuringYDBToGRDBMigration:
            return NO;
        case StorageCoordinatorStateGRDB:
        case StorageCoordinatorStateGRDBTests:
            return self.isStorageSetupComplete;
    }
}

@end

NS_ASSUME_NONNULL_END
