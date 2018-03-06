//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackup.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSBackupExport.h"
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/OWSBackupStorage.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/YapDatabaseConnection+OWS.h>

NSString *const NSNotificationNameBackupStateDidChange = @"NSNotificationNameBackupStateDidChange";

NSString *const OWSPrimaryStorage_OWSBackupCollection = @"OWSPrimaryStorage_OWSBackupCollection";
NSString *const OWSBackup_IsBackupEnabledKey = @"OWSBackup_IsBackupEnabledKey";
NSString *const OWSBackup_LastExportSuccessDateKey = @"OWSBackup_LastExportSuccessDateKey";
NSString *const OWSBackup_LastExportFailureDateKey = @"OWSBackup_LastExportFailureDateKey";

NS_ASSUME_NONNULL_BEGIN

// TODO: Observe Reachability.
@interface OWSBackup () <OWSBackupExportDelegate>

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

// This property should only be accessed on the main thread.
@property (nonatomic, nullable) OWSBackupExport *backupExport;

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

- (void)setLastExportSuccessDate:(NSDate *)value
{
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

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:NSNotificationNameBackupStateDidChange
                                                             object:nil
                                                           userInfo:nil];

    [self ensureBackupExportState];
}

- (BOOL)shouldHaveBackupExport
{
    if (!self.isBackupEnabled) {
        return NO;
    }
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        // Only start backups when app is in the background.
        return NO;
    }
    if (![TSAccountManager isRegistered]) {
        return NO;
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

    // TODO: There's other conditions that affect this decision,
    // e.g. Reachability, wifi v. cellular, etc.
    return YES;
}

- (void)ensureBackupExportState
{
    OWSAssertIsOnMainThread();

    // Start or abort a backup export if neccessary.
    if (!self.shouldHaveBackupExport && self.backupExport) {
        [self.backupExport cancel];
        self.backupExport = nil;
    } else if (self.shouldHaveBackupExport && !self.backupExport) {
        self.backupExport =
            [[OWSBackupExport alloc] initWithDelegate:self primaryStorage:[OWSPrimaryStorage sharedManager]];
        [self.backupExport startAsync];
    }

    // Update the state flag.
    OWSBackupState backupExportState = OWSBackupState_Idle;
    if (self.backupExport) {
        backupExportState = OWSBackupState_InProgress;
    } else {
        NSDate *_Nullable lastExportSuccessDate = self.lastExportSuccessDate;
        NSDate *_Nullable lastExportFailureDate = self.lastExportFailureDate;
        if (!lastExportSuccessDate && !lastExportFailureDate) {
            backupExportState = OWSBackupState_Idle;
        } else if (lastExportSuccessDate && lastExportFailureDate) {
            backupExportState = ([lastExportSuccessDate compare:lastExportFailureDate] ? OWSBackupState_Succeeded
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
        [[NSNotificationCenter defaultCenter] postNotificationNameAsync:NSNotificationNameBackupStateDidChange
                                                                 object:nil
                                                               userInfo:nil];
    }
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

#pragma mark - OWSBackupExportDelegate

// TODO: This should eventually be the backup key stored in the Signal Service
//       and retrieved with the backup PIN.
- (nullable NSData *)backupKey
{
    // We use a delegate method to avoid storing this key in memory.
    // It will eventually be stored in the keychain.
    return [@"test backup key" dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)backupExportDidSucceed:(OWSBackupExport *)backupExport
{
    if (self.backupExport != backupExport) {
        return;
    }

    DDLogInfo(@"%@ %s.", self.logTag, __PRETTY_FUNCTION__);

    self.backupExport = nil;

    [self setLastExportSuccessDate:[NSDate new]];

    [self ensureBackupExportState];
}

- (void)backupExportDidFail:(OWSBackupExport *)backupExport error:(NSError *)error
{
    if (self.backupExport != backupExport) {
        return;
    }

    DDLogInfo(@"%@ %s: %@", self.logTag, __PRETTY_FUNCTION__, error);

    self.backupExport = nil;

    [self setLastExportFailureDate:[NSDate new]];

    [self ensureBackupExportState];
}

@end

NS_ASSUME_NONNULL_END
