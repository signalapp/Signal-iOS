//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackup.h"
#import "OWSBackupExportJob.h"
#import "OWSBackupIO.h"
#import "OWSBackupImportJob.h"
#import "Signal-Swift.h"
#import <Curve25519Kit/Randomness.h>
#import <SignalServiceKit/YapDatabaseConnection+OWS.h>

NSString *const NSNotificationNameBackupStateDidChange = @"NSNotificationNameBackupStateDidChange";

NSString *const OWSPrimaryStorage_OWSBackupCollection = @"OWSPrimaryStorage_OWSBackupCollection";
NSString *const OWSBackup_IsBackupEnabledKey = @"OWSBackup_IsBackupEnabledKey";
NSString *const OWSBackup_LastExportSuccessDateKey = @"OWSBackup_LastExportSuccessDateKey";
NSString *const OWSBackup_LastExportFailureDateKey = @"OWSBackup_LastExportFailureDateKey";

NS_ASSUME_NONNULL_BEGIN

// TODO: Observe Reachability.
@interface OWSBackup () <OWSBackupJobDelegate>

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

// This property should only be accessed on the main thread.
@property (nonatomic, nullable) OWSBackupExportJob *backupExportJob;

// This property should only be accessed on the main thread.
@property (nonatomic, nullable) OWSBackupImportJob *backupImportJob;

@property (nonatomic, nullable) NSString *backupExportDescription;
@property (nonatomic, nullable) NSNumber *backupExportProgress;

@property (nonatomic, nullable) NSString *backupImportDescription;
@property (nonatomic, nullable) NSNumber *backupImportProgress;

@end

#pragma mark -

@implementation OWSBackup

@synthesize dbConnection = _dbConnection;

+ (instancetype)sharedManager
{
    static OWSBackup *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
}

- (instancetype)initDefault
{
    OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];

    return [self initWithPrimaryStorage:primaryStorage];
}

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(primaryStorage);

    _dbConnection = primaryStorage.newDatabaseConnection;

    _backupExportState = OWSBackupState_Idle;
    _backupImportState = OWSBackupState_Idle;

    OWSSingletonAssert();

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setup
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:OWSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationStateDidChange)
                                                 name:RegistrationStateDidChangeNotification
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

#pragma mark - Backup Export

- (void)tryToExportBackup
{
    OWSAssertIsOnMainThread();
    OWSAssert(!self.backupExportJob);

    if (!self.canBackupExport) {
        // TODO: Offer a reason in the UI.
        return;
    }

    // In development, make sure there's no export or import in progress.
    [self.backupExportJob cancel];
    self.backupExportJob = nil;
    [self.backupImportJob cancel];
    self.backupImportJob = nil;

    _backupExportState = OWSBackupState_InProgress;

    self.backupExportJob =
        [[OWSBackupExportJob alloc] initWithDelegate:self primaryStorage:[OWSPrimaryStorage sharedManager]];
    [self.backupExportJob startAsync];

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
    OWSAssert(value);

    [self.dbConnection setDate:value
                        forKey:OWSBackup_LastExportSuccessDateKey
                  inCollection:OWSPrimaryStorage_OWSBackupCollection];
}

- (nullable NSDate *)lastExportSuccessDate
{
    return [self.dbConnection dateForKey:OWSBackup_LastExportSuccessDateKey
                            inCollection:OWSPrimaryStorage_OWSBackupCollection];
}

- (void)setLastExportFailureDate:(NSDate *)value
{
    OWSAssert(value);

    [self.dbConnection setDate:value
                        forKey:OWSBackup_LastExportFailureDateKey
                  inCollection:OWSPrimaryStorage_OWSBackupCollection];
}


- (nullable NSDate *)lastExportFailureDate
{
    return [self.dbConnection dateForKey:OWSBackup_LastExportFailureDateKey
                            inCollection:OWSPrimaryStorage_OWSBackupCollection];
}

- (BOOL)isBackupEnabled
{
    return [self.dbConnection boolForKey:OWSBackup_IsBackupEnabledKey
                            inCollection:OWSPrimaryStorage_OWSBackupCollection
                            defaultValue:NO];
}

- (void)setIsBackupEnabled:(BOOL)value
{
    [self.dbConnection setBool:value
                        forKey:OWSBackup_IsBackupEnabledKey
                  inCollection:OWSPrimaryStorage_OWSBackupCollection];

    if (!value) {
        [self.dbConnection removeObjectForKey:OWSBackup_LastExportSuccessDateKey
                                 inCollection:OWSPrimaryStorage_OWSBackupCollection];
        [self.dbConnection removeObjectForKey:OWSBackup_LastExportFailureDateKey
                                 inCollection:OWSPrimaryStorage_OWSBackupCollection];
    }

    [self postDidChangeNotification];

    [self ensureBackupExportState];
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
    if (![TSAccountManager isRegistered]) {
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

    // Start or abort a backup export if neccessary.
    if (!self.shouldHaveBackupExport && self.backupExportJob) {
        [self.backupExportJob cancel];
        self.backupExportJob = nil;
    } else if (self.shouldHaveBackupExport && !self.backupExportJob) {
        self.backupExportJob =
            [[OWSBackupExportJob alloc] initWithDelegate:self primaryStorage:[OWSPrimaryStorage sharedManager]];
        [self.backupExportJob startAsync];
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
            OWSFail(@"%@ unexpected condition.", self.logTag);
        }
    }

    BOOL stateDidChange = _backupExportState != backupExportState;
    _backupExportState = backupExportState;
    if (stateDidChange) {
        [self postDidChangeNotification];
    }
}

#pragma mark - Backup Import

- (void)checkCanImportBackup:(OWSBackupBoolBlock)success failure:(OWSBackupErrorBlock)failure
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    [OWSBackupAPI checkForManifestInCloudWithSuccess:^(BOOL value) {
        dispatch_async(dispatch_get_main_queue(), ^{
            success(value);
        });
    }
        failure:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                failure(error);
            });
        }];
}

- (void)tryToImportBackup
{
    OWSAssertIsOnMainThread();
    OWSAssert(!self.backupImportJob);

    // In development, make sure there's no export or import in progress.
    [self.backupExportJob cancel];
    self.backupExportJob = nil;
    [self.backupImportJob cancel];
    self.backupImportJob = nil;

    _backupImportState = OWSBackupState_InProgress;

    self.backupImportJob =
        [[OWSBackupImportJob alloc] initWithDelegate:self primaryStorage:[OWSPrimaryStorage sharedManager]];
    [self.backupImportJob startAsync];

    [self postDidChangeNotification];
}

- (void)cancelImportBackup
{
    [self.backupImportJob cancel];
    self.backupImportJob = nil;

    _backupImportState = OWSBackupState_Idle;

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

    DDLogInfo(@"%@ %s.", self.logTag, __PRETTY_FUNCTION__);

    if (self.backupImportJob == backupJob) {
        self.backupImportJob = nil;

        _backupImportState = OWSBackupState_Succeeded;
    } else if (self.backupExportJob == backupJob) {
        self.backupExportJob = nil;

        [self setLastExportSuccessDate:[NSDate new]];

        [self ensureBackupExportState];
    } else {
        DDLogWarn(@"%@ obsolete job succeeded: %@", self.logTag, [backupJob class]);
        return;
    }

    [self postDidChangeNotification];
}

- (void)backupJobDidFail:(OWSBackupJob *)backupJob error:(NSError *)error
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ %s: %@", self.logTag, __PRETTY_FUNCTION__, error);

    if (self.backupImportJob == backupJob) {
        self.backupImportJob = nil;

        _backupImportState = OWSBackupState_Failed;
    } else if (self.backupExportJob == backupJob) {
        self.backupExportJob = nil;

        [self setLastExportFailureDate:[NSDate new]];

        [self ensureBackupExportState];
    } else {
        DDLogInfo(@"%@ obsolete backup job failed.", self.logTag);
        return;
    }

    [self postDidChangeNotification];
}

- (void)backupJobDidUpdate:(OWSBackupJob *)backupJob
               description:(nullable NSString *)description
                  progress:(nullable NSNumber *)progress
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

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

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    [OWSBackupAPI fetchAllRecordNamesWithSuccess:^(NSArray<NSString *> *recordNames) {
        for (NSString *recordName in [recordNames sortedArrayUsingSelector:@selector(compare:)]) {
            DDLogInfo(@"%@ \t %@", self.logTag, recordName);
        }
        DDLogInfo(@"%@ record count: %zd", self.logTag, recordNames.count);
    }
        failure:^(NSError *error) {
            DDLogError(@"%@ Failed to retrieve backup records: %@", self.logTag, error);
        }];
}

- (void)clearAllCloudKitRecords
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    [OWSBackupAPI fetchAllRecordNamesWithSuccess:^(NSArray<NSString *> *recordNames) {
        if (recordNames.count < 1) {
            DDLogInfo(@"%@ No CloudKit records found to clear.", self.logTag);
            return;
        }
        [OWSBackupAPI deleteRecordsFromCloudWithRecordNames:recordNames
            success:^{
                DDLogInfo(@"%@ Clear all CloudKit records succeeded.", self.logTag);
            }
            failure:^(NSError *error) {
                DDLogError(@"%@ Clear all CloudKit records failed: %@.", self.logTag, error);
            }];
    }
        failure:^(NSError *error) {
            DDLogError(@"%@ Failed to retrieve CloudKit records: %@", self.logTag, error);
        }];
}

#pragma mark - Lazy Restore

- (NSArray<NSString *> *)attachmentRecordNamesForLazyRestore
{
    NSMutableArray<NSString *> *recordNames = [NSMutableArray new];
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        id ext = [transaction ext:TSLazyRestoreAttachmentsDatabaseViewExtensionName];
        if (!ext) {
            OWSFail(@"%@ Could not load database view.", self.logTag);
            return;
        }

        [ext enumerateKeysAndObjectsInGroup:TSLazyRestoreAttachmentsGroup
                                 usingBlock:^(
                                     NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop) {
                                     if (![object isKindOfClass:[TSAttachmentStream class]]) {
                                         OWSFail(@"%@ Unexpected object: %@ in collection:%@",
                                             self.logTag,
                                             [object class],
                                             collection);
                                         return;
                                     }
                                     TSAttachmentStream *attachmentStream = object;
                                     if (!attachmentStream.lazyRestoreFragment) {
                                         OWSFail(@"%@ Invalid object: %@ in collection:%@",
                                             self.logTag,
                                             [object class],
                                             collection);
                                         return;
                                     }
                                     [recordNames addObject:attachmentStream.lazyRestoreFragment.recordName];
                                 }];
    }];
    return recordNames;
}

- (NSArray<NSString *> *)attachmentIdsForLazyRestore
{
    NSMutableArray<NSString *> *attachmentIds = [NSMutableArray new];
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        id ext = [transaction ext:TSLazyRestoreAttachmentsDatabaseViewExtensionName];
        if (!ext) {
            OWSFail(@"%@ Could not load database view.", self.logTag);
            return;
        }

        [ext enumerateKeysInGroup:TSLazyRestoreAttachmentsGroup
                       usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop) {
                           [attachmentIds addObject:key];
                       }];
    }];
    return attachmentIds;
}

- (void)lazyRestoreAttachment:(TSAttachmentStream *)attachment
                     backupIO:(OWSBackupIO *)backupIO
                   completion:(OWSBackupBoolBlock)completion
{
    OWSAssert(attachment);
    OWSAssert(backupIO);
    OWSAssert(completion);

    NSString *_Nullable attachmentFilePath = [attachment filePath];
    if (attachmentFilePath.length < 1) {
        DDLogError(@"%@ Attachment has invalid file path.", self.logTag);
        return completion(NO);
    }
    if ([NSFileManager.defaultManager fileExistsAtPath:attachmentFilePath]) {
        DDLogError(@"%@ Attachment already has file.", self.logTag);
        return completion(NO);
    }

    OWSBackupFragment *_Nullable lazyRestoreFragment = attachment.lazyRestoreFragment;
    if (!lazyRestoreFragment) {
        DDLogWarn(@"%@ Attachment missing lazy restore metadata.", self.logTag);
        return completion(NO);
    }
    if (lazyRestoreFragment.recordName.length < 1 || lazyRestoreFragment.encryptionKey.length < 1) {
        DDLogError(@"%@ Incomplete lazy restore metadata.", self.logTag);
        return completion(NO);
    }

    // Use a predictable file path so that multiple "import backup" attempts
    // will leverage successful file downloads from previous attempts.
    //
    // TODO: This will also require imports using a predictable jobTempDirPath.
    NSString *tempFilePath = [backupIO generateTempFilePath];

    [OWSBackupAPI downloadFileFromCloudWithRecordName:lazyRestoreFragment.recordName
        toFileUrl:[NSURL fileURLWithPath:tempFilePath]
        success:^{
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self lazyRestoreAttachment:attachment
                                   backupIO:backupIO
                          encryptedFilePath:tempFilePath
                              encryptionKey:lazyRestoreFragment.encryptionKey
                                 completion:completion];
            });
        }
        failure:^(NSError *error) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                completion(NO);
            });
        }];
}

- (void)lazyRestoreAttachment:(TSAttachmentStream *)attachment
                     backupIO:(OWSBackupIO *)backupIO
            encryptedFilePath:(NSString *)encryptedFilePath
                encryptionKey:(NSData *)encryptionKey
                   completion:(OWSBackupBoolBlock)completion
{
    OWSAssert(attachment);
    OWSAssert(backupIO);
    OWSAssert(encryptedFilePath.length > 0);
    OWSAssert(encryptionKey.length > 0);
    OWSAssert(completion);

    NSData *_Nullable data = [NSData dataWithContentsOfFile:encryptedFilePath];
    if (!data) {
        DDLogError(@"%@ Could not load encrypted file.", self.logTag);
        return completion(NO);
    }

    NSString *decryptedFilePath = [backupIO generateTempFilePath];

    @autoreleasepool {
        if (![backupIO decryptFileAsFile:encryptedFilePath dstFilePath:decryptedFilePath encryptionKey:encryptionKey]) {
            DDLogError(@"%@ Could not load decrypt file.", self.logTag);
            return completion(NO);
        }
    }

    NSString *_Nullable attachmentFilePath = [attachment filePath];
    if (attachmentFilePath.length < 1) {
        DDLogError(@"%@ Attachment has invalid file path.", self.logTag);
        return completion(NO);
    }

    NSString *attachmentDirPath = [attachmentFilePath stringByDeletingLastPathComponent];
    if (![OWSFileSystem ensureDirectoryExists:attachmentDirPath]) {
        DDLogError(@"%@ Couldn't create directory for attachment file.", self.logTag);
        return completion(NO);
    }

    NSError *error;
    BOOL success =
        [NSFileManager.defaultManager moveItemAtPath:decryptedFilePath toPath:attachmentFilePath error:&error];
    if (!success || error) {
        DDLogError(@"%@ Attachment file could not be restored: %@.", self.logTag, error);
        return completion(NO);
    }

    [attachment updateWithLazyRestoreComplete];

    completion(YES);
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
