//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TestAppContext.h"
#import "OWSFileSystem.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@interface TestAppContext ()

@property (nonatomic) SSKTestKeychainStorage *testKeychainStorage;
@property (nonatomic) NSString *mockAppDocumentDirectoryPath;
@property (nonatomic) NSString *mockAppSharedDataDirectoryPath;
@property (nonatomic) NSUserDefaults *appUserDefaults;

@end

#pragma mark -

@implementation TestAppContext

@synthesize mainWindow = _mainWindow;
@synthesize appLaunchTime = _appLaunchTime;
@synthesize appForegroundTime = _appForegroundTime;

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.testKeychainStorage = [SSKTestKeychainStorage new];

    // Avoid using OWSTemporaryDirectory(); it can consult the current app context.
    NSString *dirName = [NSString stringWithFormat:@"ows_temp_%@", NSUUID.UUID.UUIDString];
    NSString *temporaryDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:dirName];
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:temporaryDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    if (error) {
        OWSFail(@"Failed to create directory: %@, error: %@", temporaryDirectory, error);
    }

    self.mockAppDocumentDirectoryPath = [temporaryDirectory stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    self.mockAppSharedDataDirectoryPath = [temporaryDirectory stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    self.appUserDefaults = [[NSUserDefaults alloc] init];
    NSDate *launchDate = [NSDate new];
    _appLaunchTime = launchDate;
    _appForegroundTime = launchDate;

    return self;
}

- (UIApplicationState)reportedApplicationState
{
    return UIApplicationStateActive;
}

#pragma mark -

- (BOOL)isMainApp
{
    return YES;
}

- (BOOL)isMainAppAndActive
{
    return YES;
}

- (BOOL)isNSE
{
    return NO;
}

- (UIApplicationState)mainApplicationStateOnLaunch
{
    OWSFailDebug(@"Not main app.");

    return UIApplicationStateInactive;
}

- (BOOL)isRTL
{
    return NO;
}

- (CGFloat)statusBarHeight
{
    return 20;
}

- (BOOL)isInBackground
{
    return NO;
}

- (BOOL)isAppForegroundAndActive
{
    return YES;
}

- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithExpirationHandler:
    (BackgroundTaskExpirationHandler)expirationHandler
{
    return UIBackgroundTaskInvalid;
}

- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)backgroundTaskIdentifier
{
}

- (void)ensureSleepBlocking:(BOOL)shouldBeBlocking blockingObjectsDescription:(NSString *)blockingObjectsDescription
{
}

- (nullable UIViewController *)frontmostViewController
{
    return nil;
}

- (void)openSystemSettings
{
}

- (void)openURL:(NSURL *)url completion:(void (^__nullable)(BOOL))completion
{
}

- (BOOL)isRunningTests
{
    return YES;
}

- (CGRect)frame
{
    // Pretend to be a small device.
    return CGRectMake(0, 0, 300, 400);
}

- (UIInterfaceOrientation)interfaceOrientation
{
    return UIInterfaceOrientationPortrait;
}

#pragma mark -

- (void)runNowOrWhenMainAppIsActive:(AppActiveBlock)block
{
    block();
}

- (void)runAppActiveBlocks
{
}

- (id<SSKKeychainStorage>)keychainStorage
{
    return self.testKeychainStorage;
}

- (NSString *)appDocumentDirectoryPath
{
    return self.mockAppDocumentDirectoryPath;
}

- (NSString *)appSharedDataDirectoryPath
{
    return self.mockAppSharedDataDirectoryPath;
}

- (NSString *)appDatabaseBaseDirectoryPath
{
    return self.appSharedDataDirectoryPath;
}

- (BOOL)canPresentNotifications
{
    return NO;
}

- (BOOL)shouldProcessIncomingMessages
{
    return YES;
}

- (BOOL)hasUI
{
    return YES;
}

- (BOOL)hasActiveCall
{
    return NO;
}

- (NSString *)debugLogsDirPath
{
    return TestAppContext.testDebugLogsDirPath;
}

+ (NSString *)testDebugLogsDirPath
{
    NSString *dirPath = [OWSTemporaryDirectory() stringByAppendingPathComponent:@"TestLogs"];
    [OWSFileSystem ensureDirectoryExists:dirPath];
    return dirPath;
}

- (void)resetAppDataAndExit
{
    // Do nothing.
}

@end

#endif

NS_ASSUME_NONNULL_END
