//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <CocoaLumberjack/DDFileLogger.h>

NS_ASSUME_NONNULL_BEGIN

@interface DebugLogger : NSObject

+ (instancetype)sharedLogger;

- (void)enableFileLogging;

- (void)disableFileLogging;

- (void)enableTTYLogging;

- (void)enableErrorReporting;
@property (nonatomic, readonly) NSURL *errorLogsDir;

- (void)wipeLogs;

- (NSArray<NSString *> *)allLogFilePaths;

@end

NS_ASSUME_NONNULL_END
