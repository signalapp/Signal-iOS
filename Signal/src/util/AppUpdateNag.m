//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AppUpdateNag.h"
#import "RegistrationViewController.h"
#import "Signal-Swift.h"
#import <ATAppUpdater/ATAppUpdater.h>
#import <SignalServiceKit/TSStorageManager.h>

NSString *const TSStorageManagerAppUpgradeNagCollection = @"TSStorageManagerAppUpgradeNagCollection";
NSString *const TSStorageManagerAppUpgradeNagDate = @"TSStorageManagerAppUpgradeNagDate";

@interface AppUpdateNag () <ATAppUpdaterDelegate>

@property (nonatomic, readonly) TSStorageManager *storageManager;

@end

#pragma mark -

@implementation AppUpdateNag

+ (instancetype)sharedInstance
{
    static AppUpdateNag *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] initDefault];
    });
    return sharedInstance;
}

- (instancetype)initDefault
{
    TSStorageManager *storageManager = [TSStorageManager sharedManager];

    return [self initWithStorageManager:storageManager];
}

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(storageManager);

    _storageManager = storageManager;

    OWSSingletonAssert();

    return self;
}

- (void)showAppUpgradeNagIfNecessary
{
    // Only show nag if we are "at rest" in the home view or registration view without any
    // alerts or dialogs showing.
    UIViewController *frontmostViewController =
    [UIApplication sharedApplication].frontmostViewController;
    OWSAssert(frontmostViewController);
    BOOL canPresent = ([frontmostViewController isKindOfClass:[SignalsViewController class]] ||
                       [frontmostViewController isKindOfClass:[RegistrationViewController class]]);
    if (!canPresent) {
        return;
    }
    
    NSDate *lastNagDate = [[TSStorageManager sharedManager] dateForKey:TSStorageManagerAppUpgradeNagDate
                                                          inCollection:TSStorageManagerAppUpgradeNagCollection];
    const NSTimeInterval kMinute = 60.f;
    const NSTimeInterval kHour = 60 * kMinute;
    const NSTimeInterval kDay = 24 * kHour;
    const NSTimeInterval kNagFrequency = kDay * 14;
    BOOL canNag = (!lastNagDate || fabs(lastNagDate.timeIntervalSinceNow) > kNagFrequency);
    if (!canNag) {
        return;
    }

    // NOTE: The iTunes app store API exposes "short" version numbers, so
    // it isn't possible to nag about hotfix releases.
    ATAppUpdater *updater = [ATAppUpdater sharedUpdater];
    [updater setAlertTitle:NSLocalizedString(
                               @"APP_UPDATE_NAG_ALERT_TITLE", @"Title for the 'new app version available' alert.")];
    [updater setAlertMessage:NSLocalizedString(@"APP_UPDATE_NAG_ALERT_MESSAGE_FORMAT",
                                 @"Message format for the 'new app version available' alert. Embeds: {{The latest app "
                                 @"version number.}}.")];
    [updater setAlertUpdateButtonTitle:NSLocalizedString(@"APP_UPDATE_NAG_ALERT_UPDATE_BUTTON",
                                           @"Label for the 'update' button in the 'new app version available' alert.")];
    [updater setAlertCancelButtonTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")];
    [updater setDelegate:self];
    [updater showUpdateWithConfirmation];
}

#pragma mark - ATAppUpdaterDelegate

- (void)appUpdaterDidShowUpdateDialog
{
    DDLogInfo(@"%@ %s", self.tag, __PRETTY_FUNCTION__);

    [[TSStorageManager sharedManager] setDate:[NSDate new]
                                       forKey:TSStorageManagerAppUpgradeNagDate
                                 inCollection:TSStorageManagerAppUpgradeNagCollection];
}

- (void)appUpdaterUserDidLaunchAppStore
{
    DDLogInfo(@"%@ %s", self.tag, __PRETTY_FUNCTION__);
}

- (void)appUpdaterUserDidCancel
{
    DDLogInfo(@"%@ %s", self.tag, __PRETTY_FUNCTION__);
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
