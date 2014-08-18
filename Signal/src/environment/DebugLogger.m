//
//  DebugLogger.m
//  Signal
//
//  Created by Frederic Jacobs on 08/08/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "DebugLogger.h"

#pragma mark Logging - Production logging wants us to write some logs to a file in case we need it for debugging.

#import <CocoaLumberjack/DDTTYLogger.h>
#import <CocoaLumberjack/DDFileLogger.h>

@interface DebugLogger ()

@property (nonatomic) DDFileLogger *fileLogger;

@end

@implementation DebugLogger

MacrosSingletonImplemention

- (void)enableFileLogging{
    self.fileLogger = [[DDFileLogger alloc] init]; //Logging to file, because it's in the Cache folder, they are not uploaded in iTunes/iCloud backups.
    self.fileLogger.rollingFrequency = 60 * 60 * 24; // 24 hour rolling.
    self.fileLogger.logFileManager.maximumNumberOfLogFiles = 3; // Keep three days of logs.
    [DDLog addLogger:self.fileLogger];
}

- (void)disableFileLogging{
    [DDLog removeLogger:self.fileLogger];
    self.fileLogger = nil;
}

- (void)enableTTYLogging{
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
}

- (void)wipeLogs{
    BOOL reenableLogging = (self.fileLogger?YES:NO);
    
    if (reenableLogging) {
        [self disableFileLogging];
    }
    
    NSError *error;
    NSString *logPath    = [NSHomeDirectory() stringByAppendingString:@"/Library/Caches/Logs/"];
    NSArray  *logsFiles  = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:logPath error:&error];

    for (NSUInteger i = 0; i < logsFiles.count; i++) {
        [[NSFileManager defaultManager] removeItemAtPath:[logPath stringByAppendingString:logsFiles[i]] error:&error];
    }
    
    if (error) {
        DDLogError(@"Logs couldn't be removed. %@", error.description);
    }
    
    if (reenableLogging) {
        [self enableFileLogging];
    }
}

@end
