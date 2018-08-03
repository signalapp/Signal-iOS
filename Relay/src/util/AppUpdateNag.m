//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AppUpdateNag.h"
#import "RegistrationViewController.h"
#import "Relay-Swift.h"
#import <ATAppUpdater/ATAppUpdater.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>

NSString *const OWSPrimaryStorageAppUpgradeNagCollection = @"TSStorageManagerAppUpgradeNagCollection";
NSString *const OWSPrimaryStorageAppUpgradeNagDate = @"TSStorageManagerAppUpgradeNagDate";

@interface AppUpdateNag () <ATAppUpdaterDelegate>

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

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
    OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];

    return [self initWithPrimaryStorage:primaryStorage];
}

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(primaryStorage);

    _dbConnection = primaryStorage.newDatabaseConnection;

    OWSSingletonAssert();

    return self;
}

- (void)showAppUpgradeNagIfNecessary
{
    if (CurrentAppContext().isRunningTests) {
        return;
    }

    // Only show nag if we are "at rest" in the home view or registration view without any
    // alerts or dialogs showing.
    UIViewController *frontmostViewController =
    [UIApplication sharedApplication].frontmostViewController;
    OWSAssert(frontmostViewController);
    BOOL canPresent = ([frontmostViewController isKindOfClass:[HomeViewController class]] ||
        [frontmostViewController isKindOfClass:[RegistrationViewController class]]);
    if (!canPresent) {
        return;
    }

    NSDate *lastNagDate = [self.dbConnection dateForKey:OWSPrimaryStorageAppUpgradeNagDate
                                           inCollection:OWSPrimaryStorageAppUpgradeNagCollection];
    const NSTimeInterval kNagFrequency = kDayInterval * 14;
    BOOL canNag = (!lastNagDate || fabs(lastNagDate.timeIntervalSinceNow) > kNagFrequency);
    if (!canNag) {
        return;
    }

    ATAppUpdater *updater = [ATAppUpdater sharedUpdater];
    [updater setAlertTitle:NSLocalizedString(
                               @"APP_UPDATE_NAG_ALERT_TITLE", @"Title for the 'new app version available' alert.")];
    [updater setAlertMessage:NSLocalizedString(@"APP_UPDATE_NAG_ALERT_MESSAGE_FORMAT",
                                 @"Message format for the 'new app version available' alert. Embeds: {{The latest app "
                                 @"version number.}}.")];
    [updater setAlertUpdateButtonTitle:NSLocalizedString(@"APP_UPDATE_NAG_ALERT_UPDATE_BUTTON",
                                           @"Label for the 'update' button in the 'new app version available' alert.")];
    [updater setAlertCancelButtonTitle:CommonStrings.cancelButton];
    [updater setDelegate:self];
    [updater showUpdateWithConfirmation];
}

#pragma mark - ATAppUpdaterDelegate

- (void)appUpdaterDidShowUpdateDialog
{
    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    [self.dbConnection setDate:[NSDate new]
                        forKey:OWSPrimaryStorageAppUpgradeNagDate
                  inCollection:OWSPrimaryStorageAppUpgradeNagCollection];
}

- (void)appUpdaterUserDidLaunchAppStore
{
    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
}

- (void)appUpdaterUserDidCancel
{
    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
}

@end
