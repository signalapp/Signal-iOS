//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "DebugLogger.h"
#import "OWSPreferences.h"
#import "OWSScrubbingLogFormatter.h"
#import <AudioToolbox/AudioServices.h>
#import <CocoaLumberjack/DDTTYLogger.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/AppVersion.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TestAppContext.h>

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kMaxDebugLogFileSize = 1024 * 1024 * 3;

@interface DebugLogger ()

@property (nonatomic, nullable) DDFileLogger *fileLogger;

@end

@interface DebugLogFileManager : DDLogFileManagerDefault
@end

#pragma mark -

@implementation DebugLogger

+ (instancetype)shared
{
    static DebugLogger *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [self new]; });
    return shared;
}

+ (NSString *)mainAppDebugLogsDirPath
{
    NSString *dirPath = [[OWSFileSystem cachesDirectoryPath] stringByAppendingPathComponent:@"Logs"];
    [OWSFileSystem ensureDirectoryExists:dirPath];
    return dirPath;
}

+ (NSString *)shareExtensionDebugLogsDirPath
{
    NSString *dirPath =
        [[OWSFileSystem appSharedDataDirectoryPath] stringByAppendingPathComponent:@"ShareExtensionLogs"];
    [OWSFileSystem ensureDirectoryExists:dirPath];
    return dirPath;
}

+ (NSString *)nseDebugLogsDirPath
{
    NSString *dirPath = [[OWSFileSystem appSharedDataDirectoryPath] stringByAppendingPathComponent:@"NSELogs"];
    [OWSFileSystem ensureDirectoryExists:dirPath];
    return dirPath;
}

#ifdef TESTABLE_BUILD
+ (NSString *)testDebugLogsDirPath
{
    return TestAppContext.testDebugLogsDirPath;
}
#endif

+ (NSArray<NSString *> *)allLogsDirPaths
{
    // We don't need to include testDebugLogsDirPath when
    // we upload debug logs.
    return @[
        DebugLogger.mainAppDebugLogsDirPath,
        DebugLogger.shareExtensionDebugLogsDirPath,
        DebugLogger.nseDebugLogsDirPath,
    ];
}

- (NSString *)logsDirPath
{
    return CurrentAppContext().debugLogsDirPath;
}

- (void)enableFileLogging
{
    if (CurrentAppContext().isRunningTests) {
        return;
    }
    NSString *logsDirPath = [self logsDirPath];

    // Logging to file, because it's in the Cache folder, they are not uploaded in iTunes/iCloud backups.
    id<DDLogFileManager> logFileManager = [[DebugLogFileManager alloc] initWithLogsDirectory:logsDirPath
                                                                  defaultFileProtectionLevel:@""];
    self.fileLogger = [[DDFileLogger alloc] initWithLogFileManager:logFileManager];

    // 24 hour rolling.
    self.fileLogger.rollingFrequency = kDayInterval;

    if (SSKDebugFlags.extraDebugLogs) {
        // Keep extra log files in internal builds.
        self.fileLogger.logFileManager.maximumNumberOfLogFiles = 32;
    } else {
        // Keep last 3 days of logs - or last 3 logs (if logs rollover due to max file size).
        self.fileLogger.logFileManager.maximumNumberOfLogFiles = 3;
    }

    self.fileLogger.maximumFileSize = kMaxDebugLogFileSize;
    self.fileLogger.logFormatter = [OWSScrubbingLogFormatter new];

    [DDLog addLogger:self.fileLogger];
}

- (void)disableFileLogging
{
    [DDLog removeLogger:self.fileLogger];
    self.fileLogger = nil;
}

- (void)enableTTYLogging
{
    [DDLog addLogger:DDTTYLogger.sharedInstance];
}

- (NSURL *)errorLogsDir
{
    NSString *logDirPath = [OWSFileSystem.cachesDirectoryPath stringByAppendingPathComponent:@"ErrorLogs"];
    return [NSURL fileURLWithPath:logDirPath];
}

- (id<DDLogger>)errorLogger
{
    static id<DDLogger> instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        id<DDLogFileManager> logFileManager =
            [[DDLogFileManagerDefault alloc] initWithLogsDirectory:self.errorLogsDir.path
                                        defaultFileProtectionLevel:@""];

        instance = [[ErrorLogger alloc] initWithLogFileManager:logFileManager];
    });

    return instance;
}

- (void)enableErrorReporting
{
    [DDLog addLogger:self.errorLogger withLevel:DDLogLevelError];
}

- (NSArray<NSString *> *)allLogFilePaths
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableSet<NSString *> *logPathSet = [NSMutableSet new];
    for (NSString *logDirPath in DebugLogger.allLogsDirPaths) {
        NSError *error;
        for (NSString *filename in [fileManager contentsOfDirectoryAtPath:logDirPath error:&error]) {
            NSString *logPath = [logDirPath stringByAppendingPathComponent:filename];
            [logPathSet addObject:logPath];
        }
        if (error) {
            OWSFailDebug(@"Failed to find log files: %@", error);
        }
    }
    // To be extra conservative, also add all logs from log file manager.
    // This should be redundant with the logic above.
    [logPathSet addObjectsFromArray:self.fileLogger.logFileManager.unsortedLogFilePaths];
    NSArray<NSString *> *logPaths = logPathSet.allObjects;
    return [logPaths sortedArrayUsingSelector:@selector((compare:))];
}

- (void)wipeLogs
{
    NSArray<NSString *> *logFilePaths = self.allLogFilePaths;

    BOOL reenableLogging = (self.fileLogger ? YES : NO);
    if (reenableLogging) {
        [self disableFileLogging];
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    for (NSString *logFilePath in logFilePaths) {
        BOOL success = [fileManager removeItemAtPath:logFilePath error:&error];
        if (!success || error) {
            OWSFailDebug(@"Failed to delete log file: %@", error);
        }
    }

    if (reenableLogging) {
        [self enableFileLogging];
    }
}

- (void)removeObsoleteDebugLogs
{
    NSArray<NSString *> *allBundleIds = @[
        [NSBundle.mainBundle.bundleIdPrefix stringByAppendingString:@".signal"],
        [NSBundle.mainBundle.bundleIdPrefix stringByAppendingString:@".signal.shareextension"],
        [NSBundle.mainBundle.bundleIdPrefix stringByAppendingString:@".signal.SignalNSE"],

        // Obsolete, should not be included:
        // @"org.whispersystems.signal.NotificationServiceExtension",
    ];

    BOOL (^hasKnownAppId)(NSString *) = ^(NSString *logFileName) {
        for (NSString *appId in allBundleIds) {
            NSString *prefix = [appId stringByAppendingString:@" "];
            if ([logFileName hasPrefix:prefix]) {
                return YES;
            }
        }
        return NO;
    };

    NSArray<NSString *> *logFilePaths = self.allLogFilePaths;

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    for (NSString *logFilePath in logFilePaths) {
        NSString *logFileName = logFilePath.lastPathComponent;
        if (!hasKnownAppId(logFileName)) {
            OWSLogInfo(@"Removing: %@", logFileName);
            BOOL success = [fileManager removeItemAtPath:logFilePath error:&error];
            if (!success || error) {
                // Ignore failures for dotfiles that get generated in simulator environments
                if (!([Platform isSimulator] && [logFileName hasPrefix:@"."])) {
                    OWSFailDebug(@"Failed to delete log file: %@", error);
                }
            }
        }
    }
}

static NSString *const kFirstValidLogVersion = @"5.35.1";
- (void)postLaunchLogCleanup
{
    NSString *lastCompletedAppLaunch = AppVersion.shared.lastCompletedLaunchMainAppVersion;
    if ([AppVersion compareAppVersion:lastCompletedAppLaunch with:kFirstValidLogVersion] == NSOrderedAscending) {
        [self wipeLogs];
        OWSLogWarn(@"Wiped logs. (%@ < %@)", lastCompletedAppLaunch, kFirstValidLogVersion);
    }
    [self removeObsoleteDebugLogs];
}

@end

#pragma mark -

@implementation ErrorLogger

- (void)logMessage:(nonnull DDLogMessage *)logMessage
{
    [super logMessage:logMessage];
    if (OWSPreferences.isAudibleErrorLoggingEnabled) {
        [self.class playAlertSound];
    }
}

+ (void)playAlertSound
{
    // "choo-choo"
    const SystemSoundID errorSound = 1023;
    AudioServicesPlayAlertSound(errorSound);
}

@end

#pragma mark -

@implementation DebugLogFileManager

- (void)deleteLogFilesInDirectory:(NSString *)logsDirPath olderThanDate:(NSDate *)cutoffDate
{
    NSURL *logsDirectory = [NSURL fileURLWithPath:logsDirPath];
    if (!logsDirectory) {
        return;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSURL *> *logFiles = [fileManager contentsOfDirectoryAtURL:logsDirectory
                                            includingPropertiesForKeys:@[ NSURLContentModificationDateKey ]
                                                               options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 error:NULL];
    for (NSURL *logFile in logFiles) {
        if (![logFile.pathExtension isEqualToString:@"log"]) {
            // This file is not a log file; don't touch it.
            continue;
        }
        NSDate *lastModified;
        if (![logFile getResourceValue:&lastModified forKey:NSURLContentModificationDateKey error:NULL]) {
            // Couldn't get the modification date.
            continue;
        }
        if ([lastModified isAfterDate:cutoffDate]) {
            // Still within the window.
            continue;
        }
        // Attempt to remove the item, but don't stress if it fails.
        [fileManager removeItemAtURL:logFile error:NULL];
    }
}

- (void)didArchiveLogFile:(NSString *)logFilePath wasRolled:(BOOL)wasRolled
{
    if (![CurrentAppContext() isMainApp]) {
        return;
    }

    // Use this opportunity to delete old log files from extensions as well.

    // Compute an approximate "N days ago", ignoring calendars and daylight savings changes and such.
    NSDate *cutoffDate = [NSDate dateWithTimeIntervalSinceNow:self.maximumNumberOfLogFiles * -kDayInterval];

    for (NSString *logsDirPath in [DebugLogger allLogsDirPaths]) {
        if ([logsDirPath isEqual:self.logsDirectory]) {
            // Managed directly by the base class.
            continue;
        }
        [self deleteLogFilesInDirectory:logsDirPath olderThanDate:cutoffDate];
    }
}

@end

NS_ASSUME_NONNULL_END
