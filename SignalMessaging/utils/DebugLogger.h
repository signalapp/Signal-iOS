//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <CocoaLumberjack/DDFileLogger.h>

NS_ASSUME_NONNULL_BEGIN

@interface DebugLogger : NSObject

+ (instancetype)shared;

- (void)enableFileLogging;

- (void)disableFileLogging;

- (void)enableTTYLogging;

- (void)enableErrorReporting;

@property (nonatomic, readonly) NSURL *errorLogsDir;

- (void)wipeLogs;

- (void)postLaunchLogCleanup;

- (NSArray<NSString *> *)allLogFilePaths;

@property (nonatomic, readonly, class) NSString *mainAppDebugLogsDirPath;
@property (nonatomic, readonly, class) NSString *shareExtensionDebugLogsDirPath;
@property (nonatomic, readonly, class) NSString *nseDebugLogsDirPath;
#ifdef TESTABLE_BUILD
@property (nonatomic, readonly, class) NSString *testDebugLogsDirPath;
#endif

@end

#pragma mark -

@interface ErrorLogger : DDFileLogger

+ (void)playAlertSound;

@end

NS_ASSUME_NONNULL_END
