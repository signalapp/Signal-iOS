//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugLogger.h"
#import "OWSScrubbingLogFormatter.h"
#import <SignalServiceKit/NSDate+OWS.h>

#pragma mark Logging - Production logging wants us to write some logs to a file in case we need it for debugging.

#import <CocoaLumberjack/DDTTYLogger.h>

@interface DebugLogger ()

@end

@implementation DebugLogger

+ (instancetype)sharedLogger {
    static DebugLogger *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      sharedManager = [self new];
    });
    return sharedManager;
}


- (void)enableFileLogging {
    // Logging to file, because it's in the Cache folder, they are not uploaded in iTunes/iCloud backups.
    self.fileLogger = [DDFileLogger new];
    // 24 hour rolling.
    self.fileLogger.rollingFrequency = kDayInterval;
    // Keep last 3 days of logs - or last 3 logs (if logs rollover due to max file size).
    self.fileLogger.logFileManager.maximumNumberOfLogFiles = 3;
    // Raise the max file size per log file to 3 MB.
    self.fileLogger.maximumFileSize = 1024 * 1024 * 3;
    self.fileLogger.logFormatter = [OWSScrubbingLogFormatter new];

    [DDLog addLogger:self.fileLogger];
}

- (void)disableFileLogging {
    [DDLog removeLogger:self.fileLogger];
    self.fileLogger = nil;
}

- (void)enableTTYLogging {
    [DDLog addLogger:DDTTYLogger.sharedInstance];
}

- (void)wipeLogs {
    BOOL reenableLogging = (self.fileLogger ? YES : NO);
    NSError *error;
    NSArray *logsPath = self.fileLogger.logFileManager.unsortedLogFilePaths;

    if (reenableLogging) {
        [self disableFileLogging];
    }

    for (NSUInteger i = 0; i < logsPath.count; i++) {
        [[NSFileManager defaultManager] removeItemAtPath:[logsPath objectAtIndex:i] error:&error];
    }

    if (error) {
        DDLogError(@"Logs couldn't be removed. %@", error.description);
    }

    if (reenableLogging) {
        [self enableFileLogging];
    }
}

- (NSString *)logsDirectory {
    NSArray *paths          = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *baseDir       = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    NSString *logsDirectory = [baseDir stringByAppendingPathComponent:@"Logs"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:logsDirectory]) {
        NSError *error;

        [[NSFileManager defaultManager] createDirectoryAtPath:logsDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];

        if (error) {
            DDLogError(@"Log folder couldn't be created. %@", error.description);
        }
    }

    return logsDirectory;
}

@end
