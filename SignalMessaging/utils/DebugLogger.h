//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <CocoaLumberjack/DDFileLogger.h>

NS_ASSUME_NONNULL_BEGIN

@class MainAppContext;

@interface DebugLogger : NSObject

+ (instancetype)shared;

- (void)enableErrorReporting;

@property (nonatomic, readonly) NSURL *errorLogsDir;

+ (NSArray<NSString *> *)allLogsDirPaths;
- (NSArray<NSString *> *)allLogFilePaths;

@property (nonatomic, readonly, class) NSString *mainAppDebugLogsDirPath;
@property (nonatomic, readonly, class) NSString *shareExtensionDebugLogsDirPath;
@property (nonatomic, readonly, class) NSString *nseDebugLogsDirPath;
#ifdef TESTABLE_BUILD
@property (nonatomic, readonly, class) NSString *testDebugLogsDirPath;
#endif

// exposed for Swift interop
@property (nonatomic, nullable) DDFileLogger *fileLogger;

@end

#pragma mark -

@interface DebugLogFileManager : DDLogFileManagerDefault
@end

#pragma mark -

@interface ErrorLogger : DDFileLogger

+ (void)playAlertSound;

@end

NS_ASSUME_NONNULL_END
