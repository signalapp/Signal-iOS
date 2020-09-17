//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSBackup.h"
#import "OWSBackupExportJob.h"
#import "OWSBackupIO.h"
#import "OWSBackupImportJob.h"
#import "Signal-Swift.h"
#import <CloudKit/CloudKit.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const NSNotificationNameBackupStateDidChange = @"NSNotificationNameBackupStateDidChange";

NSString *const OWSBackup_IsBackupEnabledKey = @"OWSBackup_IsBackupEnabledKey";
NSString *const OWSBackup_LastExportSuccessDateKey = @"OWSBackup_LastExportSuccessDateKey";
NSString *const OWSBackup_LastExportFailureDateKey = @"OWSBackup_LastExportFailureDateKey";
NSString *const OWSBackupErrorDomain = @"OWSBackupErrorDomain";

NSString *NSStringForBackupExportState(OWSBackupState state)
{
    switch (state) {
        case OWSBackupState_Idle:
            return NSLocalizedString(@"SETTINGS_BACKUP_STATUS_IDLE", @"Indicates that app is not backing up.");
        case OWSBackupState_InProgress:
            return NSLocalizedString(@"SETTINGS_BACKUP_STATUS_IN_PROGRESS", @"Indicates that app is backing up.");
        case OWSBackupState_Failed:
            return NSLocalizedString(@"SETTINGS_BACKUP_STATUS_FAILED", @"Indicates that the last backup failed.");
        case OWSBackupState_Succeeded:
            return NSLocalizedString(@"SETTINGS_BACKUP_STATUS_SUCCEEDED", @"Indicates that the last backup succeeded.");
    }
}

NSString *NSStringForBackupImportState(OWSBackupState state)
{
    switch (state) {
        case OWSBackupState_Idle:
            return NSLocalizedString(@"SETTINGS_BACKUP_IMPORT_STATUS_IDLE", @"Indicates that app is not restoring up.");
        case OWSBackupState_InProgress:
            return NSLocalizedString(
                @"SETTINGS_BACKUP_IMPORT_STATUS_IN_PROGRESS", @"Indicates that app is restoring up.");
        case OWSBackupState_Failed:
            return NSLocalizedString(
                @"SETTINGS_BACKUP_IMPORT_STATUS_FAILED", @"Indicates that the last backup restore failed.");
        case OWSBackupState_Succeeded:
            return NSLocalizedString(
                @"SETTINGS_BACKUP_IMPORT_STATUS_SUCCEEDED", @"Indicates that the last backup restore succeeded.");
    }
}

// POST GRDB TODO: Revisit after GRDB migration.
NSArray<NSString *> *MiscCollectionsToBackup(void)
{
    return @[
        OWSBlockingManager.keyValueStore.collection,
        OWSUserProfile.collection,
        SSKIncrementingIdFinder.collectionName,
        OWSPreferencesSignalDatabaseCollection,
    ];
}

typedef NS_ENUM(NSInteger, OWSBackupErrorCode) {
    OWSBackupErrorCodeAssertionFailure = 0,
};

NSError *OWSBackupErrorWithDescription(NSString *description)
{
    return [NSError errorWithDomain:@"OWSBackupErrorDomain"
                               code:OWSBackupErrorCodeAssertionFailure
                           userInfo:@{ NSLocalizedDescriptionKey : description }];
}

// TODO: Observe Reachability.
@interface OWSBackup () <OWSBackupJobDelegate>

// This property should only be accessed on the main thread.
@property (nonatomic, nullable) OWSBackupExportJob *backupExportJob;

// This property should only be accessed on the main thread.
@property (nonatomic, nullable) OWSBackupImportJob *backupImportJob;

@property (nonatomic, nullable) NSString *backupExportDescription;
@property (nonatomic, nullable) NSNumber *backupExportProgress;

@property (nonatomic, nullable) NSString *backupImportDescription;
@property (nonatomic, nullable) NSNumber *backupImportProgress;

@property (atomic) OWSBackupState backupExportState;
@property (atomic) OWSBackupState backupImportState;

@end

#pragma mark -

@implementation OWSBackup

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (SDSKeyValueStore *)keyValueStore
{
    static SDSKeyValueStore *keyValueStore = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keyValueStore = [[SDSKeyValueStore alloc] initWithCollection:@"OWSBackupCollection"];
    });
    return keyValueStore;
}

#pragma mark -

+ (instancetype)shared
{
    OWSAssertDebug(AppEnvironment.shared.backup);

    return AppEnvironment.shared.backup;
}

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }

    self.backupExportState = OWSBackupState_Idle;
    self.backupImportState = OWSBackupState_Idle;

    OWSSingletonAssert();

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [self setup];
    }];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setup
{
    if (!OWSBackup.isFeatureEnabled) {
        return;
    }

    [OWSBackupAPI setup];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:OWSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationStateDidChange)
                                                 name:NSNotificationNameRegistrationStateDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ckAccountChanged)
                                                 name:CKAccountChangedNotification
                                               object:nil];

    // We want to start a backup if necessary on app launch, but app launch is a
    // busy time and it's important to remain responsive, so wait a few seconds before
    // starting the backup.
    //
    // TODO: Make this period longer.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self ensureBackupExportState];
    });
}

#pragma mark - Dependencies

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);
    
    return SSKEnvironment.shared.tsAccountManager;
}

+ (BOOL)isFeatureEnabled
{
    return NO;
}

#pragma mark - Backup Export

- (void)tryToExportBackup
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(!self.backupExportJob);

    if (!self.canBackupExport) {
        // TODO: Offer a reason in the UI.
        return;
    }

    if (!self.tsAccountManager.isRegisteredAndReady) {
        OWSFailDebug(@"Can't backup; not registered and ready.");
        return;
    }
    NSString *_Nullable recipientId = self.tsAccountManager.localNumber;
    if (recipientId.length < 1) {
        OWSFailDebug(@"Can't backup; missing recipientId.");
        return;
    }

    // In development, make sure there's no export or import in progress.
    [self.backupExportJob cancel];
    self.backupExportJob = nil;
    [self.backupImportJob cancel];
    self.backupImportJob = nil;

    self.backupExportState = OWSBackupState_InProgress;

    self.backupExportJob = [[OWSBackupExportJob alloc] initWithDelegate:self recipientId:recipientId];
    [self.backupExportJob start];

    [self postDidChangeNotification];
}

- (void)cancelExportBackup
{
    [self.backupExportJob cancel];
    self.backupExportJob = nil;

    [self ensureBackupExportState];
}

- (void)setLastExportSuccessDate:(NSDate *)value
{
    OWSAssertDebug(value);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setDate:value key:OWSBackup_LastExportSuccessDateKey transaction:transaction];
    });
}

- (nullable NSDate *)lastExportSuccessDate
{
    return [self.keyValueStore getDate:OWSBackup_LastExportSuccessDateKey];
}

- (void)setLastExportFailureDate:(NSDate *)value
{
    OWSAssertDebug(value);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setDate:value key:OWSBackup_LastExportFailureDateKey transaction:transaction];
    });
}

- (nullable NSDate *)lastExportFailureDate
{
    return [self.keyValueStore getDate:OWSBackup_LastExportFailureDateKey];
}

- (BOOL)isBackupEnabled
{
    return [self.keyValueStore getBool:OWSBackup_IsBackupEnabledKey defaultValue:NO];
}

- (void)setIsBackupEnabled:(BOOL)value
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setBool:value key:OWSBackup_IsBackupEnabledKey transaction:transaction];

        if (!value) {
            [self.keyValueStore removeValueForKey:OWSBackup_LastExportSuccessDateKey transaction:transaction];
            [self.keyValueStore removeValueForKey:OWSBackup_LastExportFailureDateKey transaction:transaction];
        }
    });

    [self postDidChangeNotification];

    [self ensureBackupExportState];
}

- (BOOL)hasPendingRestoreDecision
{
    return [self.tsAccountManager hasPendingBackupRestoreDecision];
}

- (void)setHasPendingRestoreDecision:(BOOL)value
{
    [self.tsAccountManager setHasPendingBackupRestoreDecision:value];
}

- (BOOL)canBackupExport
{
    if (!self.isBackupEnabled) {
        return NO;
    }
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        // Don't start backups when app is in the background.
        return NO;
    }
    if (![self.tsAccountManager isRegisteredAndReady]) {
        return NO;
    }
    return YES;
}

- (BOOL)shouldHaveBackupExport
{
    if (!self.canBackupExport) {
        return NO;
    }
    if (self.backupExportJob) {
        // If there's already a job in progress, let it complete.
        return YES;
    }
    NSDate *_Nullable lastExportSuccessDate = self.lastExportSuccessDate;
    NSDate *_Nullable lastExportFailureDate = self.lastExportFailureDate;
    // Wait N hours before retrying after a success.
    const NSTimeInterval kRetryAfterSuccess = 24 * kHourInterval;
    if (lastExportSuccessDate && fabs(lastExportSuccessDate.timeIntervalSinceNow) < kRetryAfterSuccess) {
        return NO;
    }
    // Wait N hours before retrying after a failure.
    const NSTimeInterval kRetryAfterFailure = 6 * kHourInterval;
    if (lastExportFailureDate && fabs(lastExportFailureDate.timeIntervalSinceNow) < kRetryAfterFailure) {
        return NO;
    }
    // Don't export backup if there's an import in progress.
    //
    // This conflict shouldn't occur in production since we won't enable backup
    // export until an import is complete, but this could happen in development.
    if (self.backupImportJob) {
        return NO;
    }

    // TODO: There's other conditions that affect this decision,
    // e.g. Reachability, wifi v. cellular, etc.
    return YES;
}

- (void)ensureBackupExportState
{
    OWSAssertIsOnMainThread();

    if (!OWSBackup.isFeatureEnabled) {
        return;
    }

    if (!CurrentAppContext().isMainApp) {
        return;
    }

    if (!self.tsAccountManager.isRegisteredAndReady) {
        OWSLogError(@"Can't backup; not registered and ready.");
        return;
    }
    NSString *_Nullable recipientId = self.tsAccountManager.localNumber;
    if (recipientId.length < 1) {
        OWSFailDebug(@"Can't backup; missing recipientId.");
        return;
    }

    // Start or abort a backup export if neccessary.
    if (!self.shouldHaveBackupExport && self.backupExportJob) {
        [self.backupExportJob cancel];
        self.backupExportJob = nil;
    } else if (self.shouldHaveBackupExport && !self.backupExportJob) {
        self.backupExportJob = [[OWSBackupExportJob alloc] initWithDelegate:self recipientId:recipientId];
        [self.backupExportJob start];
    }

    // Update the state flag.
    OWSBackupState backupExportState = OWSBackupState_Idle;
    if (self.backupExportJob) {
        backupExportState = OWSBackupState_InProgress;
    } else {
        NSDate *_Nullable lastExportSuccessDate = self.lastExportSuccessDate;
        NSDate *_Nullable lastExportFailureDate = self.lastExportFailureDate;
        if (!lastExportSuccessDate && !lastExportFailureDate) {
            backupExportState = OWSBackupState_Idle;
        } else if (lastExportSuccessDate && lastExportFailureDate) {
            backupExportState = ([lastExportSuccessDate isAfterDate:lastExportFailureDate] ? OWSBackupState_Succeeded
                                                                                           : OWSBackupState_Failed);
        } else if (lastExportSuccessDate) {
            backupExportState = OWSBackupState_Succeeded;
        } else if (lastExportFailureDate) {
            backupExportState = OWSBackupState_Failed;
        } else {
            OWSFailDebug(@"unexpected condition.");
        }
    }

    BOOL stateDidChange = self.backupExportState != backupExportState;
    self.backupExportState = backupExportState;
    if (stateDidChange) {
        [self postDidChangeNotification];
    }
}

#pragma mark - Backup Import

- (void)allRecipientIdsWithManifestsInCloud:(OWSBackupStringListBlock)success failure:(OWSBackupErrorBlock)failure
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    [OWSBackupAPI
        allRecipientIdsWithManifestsInCloudWithSuccess:^(NSArray<NSString *> *recipientIds) {
            dispatch_async(dispatch_get_main_queue(), ^{
                success(recipientIds);
            });
        }
        failure:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                failure(error);
            });
        }];
}

- (AnyPromise *)ensureCloudKitAccess
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    AnyPromise * (^failWithUnexpectedError)(void) = ^{
        NSError *error = [NSError errorWithDomain:OWSBackupErrorDomain
                                             code:1
                                         userInfo:@{
                                             NSLocalizedDescriptionKey : NSLocalizedString(@"BACKUP_UNEXPECTED_ERROR",
                                                 @"Error shown when backup fails due to an unexpected error.")
                                         }];
        return [AnyPromise promiseWithValue:error];
    };

    if (!self.tsAccountManager.isRegisteredAndReady) {
        OWSLogError(@"Can't backup; not registered and ready.");
        return failWithUnexpectedError();
    }
    NSString *_Nullable recipientId = self.tsAccountManager.localNumber;
    if (recipientId.length < 1) {
        OWSFailDebug(@"Can't backup; missing recipientId.");
        return failWithUnexpectedError();
    }

    return [OWSBackupAPI ensureCloudKitAccessObjc];
}

- (void)checkCanImportBackup:(OWSBackupBoolBlock)success failure:(OWSBackupErrorBlock)failure
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    if (!OWSBackup.isFeatureEnabled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            success(NO);
        });
        return;
    }

    void (^failWithUnexpectedError)(void) = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *error =
                [NSError errorWithDomain:OWSBackupErrorDomain
                                    code:1
                                userInfo:@{
                                    NSLocalizedDescriptionKey : NSLocalizedString(@"BACKUP_UNEXPECTED_ERROR",
                                        @"Error shown when backup fails due to an unexpected error.")
                                }];
            failure(error);
        });
    };

    if (!self.tsAccountManager.isRegisteredAndReady) {
        OWSLogError(@"Can't backup; not registered and ready.");
        return failWithUnexpectedError();
    }
    NSString *_Nullable recipientId = self.tsAccountManager.localNumber;
    if (recipientId.length < 1) {
        OWSFailDebug(@"Can't backup; missing recipientId.");
        return failWithUnexpectedError();
    }

    [OWSBackupAPI ensureCloudKitAccessObjc]
        .thenInBackground(^{
            return [OWSBackupAPI checkForManifestInCloudObjcWithRecipientId:recipientId];
        })
        .then(^(NSNumber *value) {
            success(value.boolValue);
        })
        .catch(^(NSError *error) {
            failure(error);
        });
}

- (void)tryToImportBackup
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(!self.backupImportJob);

    if (!self.tsAccountManager.isRegisteredAndReady) {
        OWSLogError(@"Can't restore backup; not registered and ready.");
        return;
    }
    NSString *_Nullable recipientId = self.tsAccountManager.localNumber;
    if (recipientId.length < 1) {
        OWSLogError(@"Can't restore backup; missing recipientId.");
        return;
    }

    // In development, make sure there's no export or import in progress.
    [self.backupExportJob cancel];
    self.backupExportJob = nil;
    [self.backupImportJob cancel];
    self.backupImportJob = nil;

    self.backupImportState = OWSBackupState_InProgress;

    self.backupImportJob = [[OWSBackupImportJob alloc] initWithDelegate:self recipientId:recipientId];
    [self.backupImportJob start];

    [self postDidChangeNotification];
}

- (void)cancelImportBackup
{
    [self.backupImportJob cancel];
    self.backupImportJob = nil;

    self.backupImportState = OWSBackupState_Idle;

    [self postDidChangeNotification];
}

#pragma mark -

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self ensureBackupExportState];
}

- (void)registrationStateDidChange
{
    OWSAssertIsOnMainThread();

    [self ensureBackupExportState];

    [self postDidChangeNotification];
}

- (void)ckAccountChanged
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ensureBackupExportState];
        
        [self postDidChangeNotification];
    });
}

#pragma mark - OWSBackupJobDelegate

// We use a delegate method to avoid storing this key in memory.
- (nullable NSData *)backupEncryptionKey
{
    // TODO: Use actual encryption key.
    return [@"temp" dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)backupJobDidSucceed:(OWSBackupJob *)backupJob
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@".");

    if (self.backupImportJob == backupJob) {
        self.backupImportJob = nil;

        self.backupImportState = OWSBackupState_Succeeded;
    } else if (self.backupExportJob == backupJob) {
        self.backupExportJob = nil;

        [self setLastExportSuccessDate:[NSDate new]];

        [self ensureBackupExportState];
    } else {
        OWSLogWarn(@"obsolete job succeeded: %@", [backupJob class]);
        return;
    }

    [self postDidChangeNotification];
}

- (void)backupJobDidFail:(OWSBackupJob *)backupJob error:(NSError *)error
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@": %@", error);

    if (self.backupImportJob == backupJob) {
        self.backupImportJob = nil;

        self.backupImportState = OWSBackupState_Failed;
    } else if (self.backupExportJob == backupJob) {
        self.backupExportJob = nil;

        [self setLastExportFailureDate:[NSDate new]];

        [self ensureBackupExportState];
    } else {
        OWSLogInfo(@"obsolete backup job failed.");
        return;
    }

    [self postDidChangeNotification];
}

- (void)backupJobDidUpdate:(OWSBackupJob *)backupJob
               description:(nullable NSString *)description
                  progress:(nullable NSNumber *)progress
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    // TODO: Should we consolidate this state?
    BOOL didChange;
    if (self.backupImportJob == backupJob) {
        didChange = !([NSObject isNullableObject:self.backupImportDescription equalTo:description] &&
            [NSObject isNullableObject:self.backupImportProgress equalTo:progress]);

        self.backupImportDescription = description;
        self.backupImportProgress = progress;
    } else if (self.backupExportJob == backupJob) {
        didChange = !([NSObject isNullableObject:self.backupExportDescription equalTo:description] &&
            [NSObject isNullableObject:self.backupExportProgress equalTo:progress]);

        self.backupExportDescription = description;
        self.backupExportProgress = progress;
    } else {
        return;
    }

    if (didChange) {
        [self postDidChangeNotification];
    }
}

- (void)logBackupRecords
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    if (!self.tsAccountManager.isRegisteredAndReady) {
        OWSLogError(@"Can't interact with backup; not registered and ready.");
        return;
    }
    NSString *_Nullable recipientId = self.tsAccountManager.localNumber;
    if (recipientId.length < 1) {
        OWSLogError(@"Can't interact with backup; missing recipientId.");
        return;
    }

    [OWSBackupAPI fetchAllRecordNamesWithRecipientId:recipientId
        success:^(NSArray<NSString *> *recordNames) {
            for (NSString *recordName in [recordNames sortedArrayUsingSelector:@selector(compare:)]) {
                OWSLogInfo(@"\t %@", recordName);
            }
            OWSLogInfo(@"record count: %zd", recordNames.count);
        }
        failure:^(NSError *error) {
            OWSLogError(@"Failed to retrieve backup records: %@", error);
        }];
}

- (void)clearAllCloudKitRecords
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    if (!self.tsAccountManager.isRegisteredAndReady) {
        OWSLogError(@"Can't interact with backup; not registered and ready.");
        return;
    }
    NSString *_Nullable recipientId = self.tsAccountManager.localNumber;
    if (recipientId.length < 1) {
        OWSLogError(@"Can't interact with backup; missing recipientId.");
        return;
    }

    [OWSBackupAPI fetchAllRecordNamesWithRecipientId:recipientId
        success:^(NSArray<NSString *> *recordNames) {
            if (recordNames.count < 1) {
                OWSLogInfo(@"No CloudKit records found to clear.");
                return;
            }
            [OWSBackupAPI deleteRecordsFromCloudWithRecordNames:recordNames
                success:^{
                    OWSLogInfo(@"Clear all CloudKit records succeeded.");
                }
                failure:^(NSError *error) {
                    OWSLogError(@"Clear all CloudKit records failed: %@.", error);
                }];
        }
        failure:^(NSError *error) {
            OWSLogError(@"Failed to retrieve CloudKit records: %@", error);
        }];
}

#pragma mark - Lazy Restore

- (NSArray<NSString *> *)attachmentRecordNamesForLazyRestore
{
    NSMutableArray<NSString *> *recordNames = [NSMutableArray new];
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        [AttachmentFinder
            enumerateAttachmentPointersWithLazyRestoreFragmentsWithTransaction:transaction
                                                                         block:^(TSAttachmentPointer *attachmentPointer,
                                                                             BOOL *stop) {
                                                                             OWSBackupFragment
                                                                                 *_Nullable lazyRestoreFragment
                                                                                 = [attachmentPointer
                                                                                     lazyRestoreFragmentWithTransaction:
                                                                                         transaction];
                                                                             if (lazyRestoreFragment == nil) {
                                                                                 OWSFailDebug(
                                                                                     @"Missing lazyRestoreFragment.");
                                                                                 return;
                                                                             }
                                                                             [recordNames addObject:lazyRestoreFragment
                                                                                                        .recordName];
                                                                         }];
    }];
    return recordNames;
}

- (NSArray<NSString *> *)attachmentIdsForLazyRestore
{
    NSMutableArray<NSString *> *attachmentIds = [NSMutableArray new];
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        // TODO: We could just enumerate the ids and not deserialize the attachments.
        [AttachmentFinder
            enumerateAttachmentPointersWithLazyRestoreFragmentsWithTransaction:transaction
                                                                         block:^(TSAttachmentPointer *attachmentPointer,
                                                                             BOOL *stop) {
                                                                             [attachmentIds
                                                                                 addObject:attachmentPointer.uniqueId];
                                                                         }];
    }];
    return attachmentIds;
}

- (AnyPromise *)lazyRestoreAttachment:(TSAttachmentPointer *)attachment backupIO:(OWSBackupIO *)backupIO
{
    OWSAssertDebug(attachment);
    OWSAssertDebug(backupIO);

    __block OWSBackupFragment *_Nullable lazyRestoreFragment;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        lazyRestoreFragment = [attachment lazyRestoreFragmentWithTransaction:transaction];
    }];
    if (lazyRestoreFragment == nil) {
        OWSLogError(@"Attachment missing lazy restore metadata.");
        return
            [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Attachment missing lazy restore metadata.")];
    }
    if (lazyRestoreFragment.recordName.length < 1 || lazyRestoreFragment.encryptionKey.length < 1) {
        OWSLogError(@"Incomplete lazy restore metadata.");
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Incomplete lazy restore metadata.")];
    }

    // Use a predictable file path so that multiple "import backup" attempts
    // will leverage successful file downloads from previous attempts.
    //
    // TODO: This will also require imports using a predictable jobTempDirPath.
    NSString *tempFilePath = [backupIO generateTempFilePath];

    return [OWSBackupAPI downloadFileFromCloudObjcWithRecordName:lazyRestoreFragment.recordName
                                                       toFileUrl:[NSURL fileURLWithPath:tempFilePath]]
        .thenInBackground(^{
            return [self lazyRestoreAttachment:attachment
                                      backupIO:backupIO
                             encryptedFilePath:tempFilePath
                                 encryptionKey:lazyRestoreFragment.encryptionKey];
        });
}

- (AnyPromise *)lazyRestoreAttachment:(TSAttachmentPointer *)attachmentPointer
                             backupIO:(OWSBackupIO *)backupIO
                    encryptedFilePath:(NSString *)encryptedFilePath
                        encryptionKey:(NSData *)encryptionKey
{
    OWSAssertDebug(attachmentPointer);
    OWSAssertDebug(backupIO);
    OWSAssertDebug(encryptedFilePath.length > 0);
    OWSAssertDebug(encryptionKey.length > 0);

    NSData *_Nullable data = [NSData dataWithContentsOfFile:encryptedFilePath];
    if (!data) {
        OWSLogError(@"Could not load encrypted file.");
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Could not load encrypted file.")];
    }

    NSString *decryptedFilePath = [backupIO generateTempFilePath];

    @autoreleasepool {
        if (![backupIO decryptFileAsFile:encryptedFilePath dstFilePath:decryptedFilePath encryptionKey:encryptionKey]) {
            OWSLogError(@"Could not load decrypt file.");
            return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Could not load decrypt file.")];
        }
    }

    __block TSAttachmentStream *stream;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        stream = [[TSAttachmentStream alloc] initWithPointer:attachmentPointer transaction:transaction];
    }];

    NSString *attachmentFilePath = stream.originalFilePath;
    if (attachmentFilePath.length < 1) {
        OWSLogError(@"Attachment has invalid file path.");
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Attachment has invalid file path.")];
    }

    NSString *attachmentDirPath = [attachmentFilePath stringByDeletingLastPathComponent];
    if (![OWSFileSystem ensureDirectoryExists:attachmentDirPath]) {
        OWSLogError(@"Couldn't create directory for attachment file.");
        return [AnyPromise
            promiseWithValue:OWSBackupErrorWithDescription(@"Couldn't create directory for attachment file.")];
    }

    if (![OWSFileSystem deleteFileIfExists:attachmentFilePath]) {
        OWSFailDebug(@"Couldn't delete existing file at attachment path.");
        return [AnyPromise
            promiseWithValue:OWSBackupErrorWithDescription(@"Couldn't delete existing file at attachment path.")];
    }

    NSError *error;
    BOOL success =
        [NSFileManager.defaultManager moveItemAtPath:decryptedFilePath toPath:attachmentFilePath error:&error];
    if (!success || error) {
        OWSLogError(@"Attachment file could not be restored: %@.", error);
        return [AnyPromise promiseWithValue:error];
    }

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        // This should overwrite the attachment pointer with an attachment stream.
        //
        // Since our "any" methods are strict about "insert vs. update", we need to
        // explicitly remove the existing pointer before inserting the stream.
        TSAttachment *_Nullable oldValue = [TSAttachment anyFetchWithUniqueId:stream.uniqueId transaction:transaction];
        if (oldValue != nil) {
            if ([oldValue isKindOfClass:[TSAttachmentStream class]]) {
                OWSFailDebug(@"Unexpected stream found.");
                return;
            }
            [oldValue anyRemoveWithTransaction:transaction];
        }
        [stream anyInsertWithTransaction:transaction];
    });

    return [AnyPromise promiseWithValue:@(1)];
}

- (void)logBackupMetadataCache
{
    OWSLogInfo(@"");

    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        [OWSBackupFragment anyEnumerateWithTransaction:transaction
                                               batched:YES
                                                 block:^(OWSBackupFragment *fragment, BOOL *stop) {
                                                     OWSLogVerbose(@"fragment: %@, %@, %lu, %@, %@, %@, %@",
                                                         fragment.uniqueId,
                                                         fragment.recordName,
                                                         (unsigned long)fragment.encryptionKey.length,
                                                         fragment.relativeFilePath,
                                                         fragment.attachmentId,
                                                         fragment.downloadFilePath,
                                                         fragment.uncompressedDataLength);
                                                 }];
        OWSLogVerbose(
            @"Number of fragments: %lu", (unsigned long)[OWSBackupFragment anyCountWithTransaction:transaction]);
    }];
}

#pragma mark - Notifications

- (void)postDidChangeNotification
{
    OWSAssertIsOnMainThread();

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:NSNotificationNameBackupStateDidChange
                                                             object:nil
                                                           userInfo:nil];
}

@end

NS_ASSUME_NONNULL_END
