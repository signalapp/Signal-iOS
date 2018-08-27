//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DebugLogger.h"
#import "OWSScrubbingLogFormatter.h"
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/OWSFileSystem.h>

#pragma mark Logging - Production logging wants us to write some logs to a file in case we need it for debugging.
#import <CocoaLumberjack/DDTTYLogger.h>

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kMaxDebugLogFileSize = 1024 * 1024 * 3;

@interface DebugLogger ()

@property (nonatomic, nullable) DDFileLogger *fileLogger;

@end

#pragma mark -

@implementation DebugLogger

+ (instancetype)sharedLogger
{
    static DebugLogger *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [self new];
    });
    return sharedManager;
}

+ (NSString *)mainAppLogsDirPath
{
    NSString *dirPath = [[OWSFileSystem cachesDirectoryPath] stringByAppendingPathComponent:@"Logs"];
    [OWSFileSystem ensureDirectoryExists:dirPath];
    return dirPath;
}

+ (NSString *)shareExtensionLogsDirPath
{
    NSString *dirPath =
        [[OWSFileSystem appSharedDataDirectoryPath] stringByAppendingPathComponent:@"ShareExtensionLogs"];
    [OWSFileSystem ensureDirectoryExists:dirPath];
    return dirPath;
}

- (NSString *)logsDirPath
{
    // This assumes that the only app extension is the share app extension.
    return (CurrentAppContext().isMainApp ? DebugLogger.mainAppLogsDirPath : DebugLogger.shareExtensionLogsDirPath);
}

- (void)enableFileLogging
{
    NSString *logsDirPath = [self logsDirPath];

    // Logging to file, because it's in the Cache folder, they are not uploaded in iTunes/iCloud backups.
    id<DDLogFileManager> logFileManager =
        [[DDLogFileManagerDefault alloc] initWithLogsDirectory:logsDirPath defaultFileProtectionLevel:@""];
    self.fileLogger = [[DDFileLogger alloc] initWithLogFileManager:logFileManager];

    // 24 hour rolling.
    self.fileLogger.rollingFrequency = kDayInterval;
    // Keep last 3 days of logs - or last 3 logs (if logs rollover due to max file size).
    self.fileLogger.logFileManager.maximumNumberOfLogFiles = 3;
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

- (NSArray<NSString *> *)allLogFilePaths
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableSet<NSString *> *logPathSet = [NSMutableSet new];
    for (NSString *logDirPath in @[
             DebugLogger.mainAppLogsDirPath,
             DebugLogger.shareExtensionLogsDirPath,
         ]) {
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

@end

NS_ASSUME_NONNULL_END
