//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TestAppContext.h"
#import <SignalServiceKit/OWSFileSystem.h>
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
@synthesize buildTime = _buildTime;

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.testKeychainStorage = [SSKTestKeychainStorage new];

    NSString *temporaryDirectory = OWSTemporaryDirectory();
    self.mockAppDocumentDirectoryPath = [temporaryDirectory stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    self.mockAppSharedDataDirectoryPath = [temporaryDirectory stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    self.appUserDefaults = [[NSUserDefaults alloc] init];
    _appLaunchTime = [NSDate new];

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

- (BOOL)isRTL
{
    return NO;
}

- (void)setStatusBarHidden:(BOOL)isHidden animated:(BOOL)isAnimated
{
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

- (void)ensureSleepBlocking:(BOOL)shouldBeBlocking blockingObjects:(NSArray<id> *)blockingObjects
{
}

- (void)setMainAppBadgeNumber:(NSInteger)value
{
}

- (nullable UIViewController *)frontmostViewController
{
    return nil;
}

- (nullable UIAlertAction *)openSystemSettingsActionWithCompletion:(void (^_Nullable)(void))completion
{
    return nil;
}

- (BOOL)isRunningTests
{
    return YES;
}

- (NSDate *)buildTime
{
    if (!_buildTime) {
        _buildTime = [NSDate new];
    }
    return _buildTime;
}

- (UIInterfaceOrientation)interfaceOrientation
{
    return UIInterfaceOrientationPortrait;
}

- (void)setNetworkActivityIndicatorVisible:(BOOL)value
{
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

@end

#endif

NS_ASSUME_NONNULL_END
