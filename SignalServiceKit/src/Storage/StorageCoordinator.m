//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "StorageCoordinator.h"
#import "AppReadiness.h"
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

NSString *NSStringForDataStore(DataStore value)
{
    switch (value) {
        case DataStoreYdb:
            return @"DataStoreYdb";
        case DataStoreGrdb:
            return @"DataStoreGrdb";
    }
}

#pragma mark -

@interface StorageCoordinator () <SDSDatabaseStorageDelegate>

@property (atomic) StorageCoordinatorState state;

@property (atomic) BOOL isStorageSetupComplete;

@property (nonatomic, readonly) DataStore dataStoreForUI;

@end

#pragma mark -

@implementation StorageCoordinator

#pragma mark - Dependencies

+ (id<NotificationsProtocol>)notificationsManager
{
    return SSKEnvironment.shared.notificationsManager;
}

#pragma mark -

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    _dataStoreForUI = [StorageCoordinator computeDataStoreForUI];

    OWSLogInfo(@"dataStoreForUI: %@", NSStringForDataStore(self.dataStoreForUI));

    _databaseStorage = [[SDSDatabaseStorage alloc] initWithDelegate:self];

    [self configure];

    return self;
}

+ (BOOL)hasYdbFile
{
    NSString *ydbFilePath = OWSPrimaryStorage.sharedDataDatabaseFilePath;
    BOOL hasYdbFile = [OWSFileSystem fileOrFolderExistsAtPath:ydbFilePath];

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

+ (BOOL)hasUnmigratedYdbFile
{
    return self.hasYdbFile && ![SSKPreferences isYdbMigrated];
}

+ (BOOL)hasInvalidDatabaseVersion
{
    BOOL prefersYdb = SSKFeatureFlags.storageMode == StorageModeYdbForAll;
    BOOL willUseYdb = StorageCoordinator.dataStoreForUI == DataStoreYdb;

    BOOL hasValidGrdb = self.hasGrdbFile;
    if (self.hasUnmigratedYdbFile) {
        hasValidGrdb = NO;
    }

    // A check to avoid trying to revert to YDB when we've already migrated to GRDB.
    if ((prefersYdb || willUseYdb) && hasValidGrdb) {
        OWSFailDebug(@"Reverting to YDB.");
        return YES;
    }

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

- (BOOL)isMigrating
{
    StorageCoordinatorState state = self.state;
    return (state == StorageCoordinatorStateBeforeYDBToGRDBMigration
        || state == StorageCoordinatorStateDuringYDBToGRDBMigration);
}

+ (DataStore)dataStoreForUI
{
    // Computing dataStoreForUI is slightly expensive.
    // Once SSKEnvironment is configured, we use the cached value
    // that hangs on StorageCoordinator.  Until then, we compute every
    // time.
    if (!SSKEnvironment.hasShared) {
        return self.computeDataStoreForUI;
    }

    return SSKEnvironment.shared.storageCoordinator.dataStoreForUI;
}

+ (DataStore)computeDataStoreForUI
{
    // NOTE: By now, any move of YDB from the "app container"
    //       to the "shared container" should be complete, so
    //       we can ignore the "legacy" database files.
    BOOL hasYdbFile = self.hasYdbFile;
    BOOL hasGrdbFile = self.hasGrdbFile;
    BOOL hasUnmigratedYdbFile = self.hasUnmigratedYdbFile;
    BOOL isNewUser = !hasYdbFile && !hasGrdbFile;

    // In the GRDB-possible modes, avoid migrations in certain cases.
    switch (SSKFeatureFlags.storageMode) {
        case StorageModeYdbForAll:
            break;
        case StorageModeGrdbForAlreadyMigrated:
        case StorageModeGrdbForLegacyUsersOnly:
        case StorageModeGrdbForNewUsersOnly:
        case StorageModeGrdbForAll:
        case StorageModeGrdbThrowawayIfMigrating:
            if (CurrentAppContext().isRunningTests) {
                // Do nothing.
            } else if (hasUnmigratedYdbFile) {
                if (!CurrentAppContext().canPresentNotifications) {
                    // Don't migrate the database in an app extension
                    // unless it can present notifications.
                    OWSFail(@"Avoiding YDB-to-GRDB migration in app extension.");
                }
                if (CurrentAppContext().mainApplicationStateOnLaunch == UIApplicationStateBackground) {
                    OWSLogInfo(@"Avoiding YDB-to-GRDB migration in background.");
                    // If we are migrating the database and the app was launched into the background,
                    // show the "GRDB migration" notification in case the migration fails.
                    [self showGRDBMigrationNotification];
                }
            }
            break;
        case StorageModeYdbTests:
        case StorageModeGrdbTests:
            break;
    }

    switch (SSKFeatureFlags.storageMode) {
        case StorageModeYdbForAll:
            return DataStoreYdb;
        case StorageModeGrdbForAlreadyMigrated:
            if (isNewUser) {
                // New users should use YDB.
                return DataStoreYdb;
            } else if (hasUnmigratedYdbFile) {
                // Existing users should use YDB.
                return DataStoreYdb;
            } else {
                // Only users who have already migrated to GRDB should use GRDB.
                return DataStoreGrdb;
            }
        case StorageModeGrdbForLegacyUsersOnly:
            if (isNewUser) {
                // New users should use YDB.
                return DataStoreYdb;
            } else {
                return DataStoreGrdb;
            }
        case StorageModeGrdbForNewUsersOnly:
            if (isNewUser) {
                // New users should use GRDB.
                return DataStoreGrdb;
            } else if (hasUnmigratedYdbFile) {
                return DataStoreYdb;
            } else {
                return DataStoreGrdb;
            }
        case StorageModeGrdbForAll:
        case StorageModeGrdbThrowawayIfMigrating:
            return DataStoreGrdb;
        case StorageModeYdbTests:
            return DataStoreYdb;
        case StorageModeGrdbTests:
            return DataStoreGrdb;
    }
}

+ (BOOL)isReadyForShareExtension
{
    OWSAssertDebug(SSKFeatureFlags.storageMode == StorageModeGrdbForAll);

    // NOTE: By now, any move of YDB from the "app container"
    //       to the "shared container" should be complete, so
    //       we can ignore the "legacy" database files.
    BOOL hasUnmigratedYdbFile = self.hasUnmigratedYdbFile;
    OWSLogInfo(@"hasUnmigratedYdbFile: %d", hasUnmigratedYdbFile);

    return !hasUnmigratedYdbFile;
}

+ (void)showGRDBMigrationNotification
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Dispatch async so that Environments are configured.
        dispatch_async(dispatch_get_main_queue(), ^{
            OWSLogInfo(@"");
            // This notification be cleared by:
            //
            // * Main app when it becomes active (along with the other notifications).
            // * When any other notification is presented (e.g. if processing
            //   background notifications).
            [self.notificationsManager notifyUserForGRDBMigration];
        });
    });
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

    BOOL hasUnmigratedYdbFile = self.class.hasUnmigratedYdbFile;
    OWSLogInfo(@"hasUnmigratedYdbFile: %d", hasUnmigratedYdbFile);

    OWSLogInfo(@"didEverUseYdb: %d", SSKPreferences.didEverUseYdb);

    switch (SSKFeatureFlags.storageMode) {
        case StorageModeYdbForAll:
        case StorageModeGrdbForAll:
        case StorageModeGrdbForAlreadyMigrated:
        case StorageModeGrdbForLegacyUsersOnly:
        case StorageModeGrdbForNewUsersOnly:
        case StorageModeGrdbThrowawayIfMigrating:
            if (self.dataStoreForUI == DataStoreYdb) {
                self.state = StorageCoordinatorStateYDB;
            } else {
                if (SSKFeatureFlags.storageMode == StorageModeGrdbThrowawayIfMigrating) {
                    // Clear flag to force migration.
                    [SSKPreferences setIsYdbMigrated:NO];
                }

                if (hasUnmigratedYdbFile) {
                    self.state = StorageCoordinatorStateBeforeYDBToGRDBMigration;

                    // We might want to delete any existing GRDB database
                    // files here, since they represent an incomplete
                    // previous migration and might cause problems.
                    [self.databaseStorage deleteGrdbFiles];
                } else {
                    self.state = StorageCoordinatorStateGRDB;

                    [self removeYdbFiles];
                }
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
    
    [self.databaseStorage logAllFileSizes];

    OWSLogInfo(@"state: %@", NSStringFromStorageCoordinatorState(self.state));
}

- (void)migrationYDBToGRDBDidComplete
{
    // These are crashing asserts.
    OWSAssert(self.state == StorageCoordinatorStateDuringYDBToGRDBMigration);

    self.state = StorageCoordinatorStateGRDB;

    OWSLogInfo(@"state: %@", NSStringFromStorageCoordinatorState(self.state));

    [self.databaseStorage logAllFileSizes];
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
    _dataStoreForUI = DataStoreGrdb;
}

- (void)useYDBForTests
{
    self.state = StorageCoordinatorStateYDBTests;
    _dataStoreForUI = DataStoreYdb;
}
#endif

- (void)removeYdbFiles
{
    if (SSKFeatureFlags.storageMode == StorageModeGrdbThrowawayIfMigrating) {
        // Don't clean up YDB; we're in throwaway mode.
        return;
    }

    [OWSStorage deleteDatabaseFiles];
    [OWSStorage deleteDBKeys];
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
