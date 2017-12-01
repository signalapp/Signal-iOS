//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <CocoaLumberjack/DDFileLogger.h>

@interface DebugLogger : NSObject

@property (nonatomic) DDFileLogger *fileLogger;

+ (instancetype)sharedLogger;

- (void)enableFileLogging;

- (void)disableFileLogging;

- (void)enableTTYLogging;

- (void)wipeLogs;

- (NSArray<NSString *> *)allLogFilePaths;

@end
