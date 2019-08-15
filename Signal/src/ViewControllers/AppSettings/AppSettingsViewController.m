//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "AppSettingsViewController.h"
#import "AboutTableViewController.h"
#import "AdvancedSettingsTableViewController.h"
#import "DebugUITableViewController.h"
#import "NotificationSettingsViewController.h"
#import "OWSBackup.h"
#import "OWSBackupSettingsViewController.h"
#import "OWSLinkedDevicesTableViewController.h"
#import "OWSNavigationController.h"
#import "PrivacySettingsTableViewController.h"
#import "ProfileViewController.h"
#import "RegistrationUtils.h"
#import "Signal-Swift.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSSocketManager.h>

@interface AppSettingsViewController ()

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, nullable) OWSInviteFlow *inviteFlow;

@end

#pragma mark -

@implementation AppSettingsViewController

/**
 * We always present the settings controller modally, from within an OWSNavigationController
 */
+ (OWSNavigationController *)inModalNavigationController
{
    AppSettingsViewController *viewController = [AppSettingsViewController new];
    OWSNavigationController *navController =
        [[OWSNavigationController alloc] initWithRootViewController:viewController];

    return navController;
}

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _contactsManager = Environment.shared.contactsManager;

    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    _contactsManager = Environment.shared.contactsManager;

    return self;
}

- (void)loadView
{
    self.tableViewStyle = UITableViewStylePlain;
    [super loadView];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.navigationItem setHidesBackButton:YES];

    OWSAssertDebug([self.navigationController isKindOfClass:[OWSNavigationController class]]);

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                      target:self
                                                      action:@selector(dismissWasPressed:)
                                     accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"dismiss")];
    [self updateRightBarButtonForTheme];
    [self observeNotifications];

    self.title = NSLocalizedString(@"SETTINGS_NAV_BAR_TITLE", @"Title for settings activity");

    [self updateTableContents];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self updateTableContents];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak AppSettingsViewController *weakSelf = self;

#ifdef INTERNAL
    OWSTableSection *internalSection = [OWSTableSection new];
    [section addItem:[OWSTableItem softCenterLabelItemWithText:@"Internal Build"]];
    [contents addSection:internalSection];
#endif

    OWSTableSection *section = [OWSTableSection new];
    [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
        return [weakSelf profileHeaderCell];
    }
                         customRowHeight:100.f
                         actionBlock:^{
                             [weakSelf showProfile];
                         }]];

    if (OWSSignalService.sharedInstance.isCensorshipCircumventionActive) {
        [section
            addItem:[OWSTableItem disclosureItemWithText:
                                      NSLocalizedString(@"NETWORK_STATUS_CENSORSHIP_CIRCUMVENTION_ACTIVE",
                                          @"Indicates to the user that censorship circumvention has been activated.")
                                             actionBlock:^{
                                                 [weakSelf showAdvanced];
                                             }]];
    } else {
        [section addItem:[OWSTableItem
                             itemWithCustomCellBlock:^{
                                 UITableViewCell *cell = [OWSTableItem newCell];
                                 cell.textLabel.text = NSLocalizedString(@"NETWORK_STATUS_HEADER", @"");
                                 cell.selectionStyle = UITableViewCellSelectionStyleNone;
                                 UILabel *accessoryLabel = [UILabel new];
                                 if (TSAccountManager.sharedInstance.isDeregistered) {
                                     accessoryLabel.text = NSLocalizedString(@"NETWORK_STATUS_DEREGISTERED",
                                         @"Error indicating that this device is no longer registered.");
                                     accessoryLabel.textColor = [UIColor ows_redColor];
                                 } else {
                                     switch (TSSocketManager.shared.highestSocketState) {
                                         case OWSWebSocketStateClosed:
                                             accessoryLabel.text = NSLocalizedString(@"NETWORK_STATUS_OFFLINE", @"");
                                             accessoryLabel.textColor = [UIColor ows_redColor];
                                             break;
                                         case OWSWebSocketStateConnecting:
                                             accessoryLabel.text = NSLocalizedString(@"NETWORK_STATUS_CONNECTING", @"");
                                             accessoryLabel.textColor = [UIColor ows_yellowColor];
                                             break;
                                         case OWSWebSocketStateOpen:
                                             accessoryLabel.text = NSLocalizedString(@"NETWORK_STATUS_CONNECTED", @"");
                                             accessoryLabel.textColor = [UIColor ows_greenColor];
                                             break;
                                     }
                                 }
                                 [accessoryLabel sizeToFit];
                                 cell.accessoryView = accessoryLabel;
                                 cell.accessibilityIdentifier
                                     = ACCESSIBILITY_IDENTIFIER_WITH_NAME(AppSettingsViewController, @"network_status");
                                 return cell;
                             }
                                         actionBlock:nil]];
    }

    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_INVITE_TITLE",
                                                              @"Settings table view cell label")
                                  accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"invite")
                                              actionBlock:^{
                                                  [weakSelf showInviteFlow];
                                              }]];
    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_PRIVACY_TITLE",
                                                              @"Settings table view cell label")
                                  accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"privacy")
                                              actionBlock:^{
                                                  [weakSelf showPrivacy];
                                              }]];
    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_NOTIFICATIONS", nil)
                                  accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"notifications")
                                              actionBlock:^{
                                                  [weakSelf showNotifications];
                                              }]];
    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"LINKED_DEVICES_TITLE",
                                                              @"Menu item and navbar title for the device manager")
                                  accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"linked_devices")
                                              actionBlock:^{
                                                  [weakSelf showLinkedDevices];
                                              }]];
    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_ADVANCED_TITLE", @"")
                                  accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"advanced")
                                              actionBlock:^{
                                                  [weakSelf showAdvanced];
                                              }]];
    BOOL isBackupEnabled = [OWSBackup.sharedManager isBackupEnabled];
    BOOL showBackup = (OWSBackup.isFeatureEnabled && isBackupEnabled);
    if (showBackup) {
        [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_BACKUP",
                                                                  @"Label for the backup view in app settings.")
                                      accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"backup")
                                                  actionBlock:^{
                                                      [weakSelf showBackup];
                                                  }]];
    }
    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_ABOUT", @"")
                                  accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"about")
                                              actionBlock:^{
                                                  [weakSelf showAbout];
                                              }]];

#ifdef USE_DEBUG_UI
    [section addItem:[OWSTableItem disclosureItemWithText:@"Debug UI"
                                  accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"debugui")
                                              actionBlock:^{
                                                  [weakSelf showDebugUI];
                                              }]];
#endif

    if (TSAccountManager.sharedInstance.isDeregistered) {
        [section addItem:[self destructiveButtonItemWithTitle:NSLocalizedString(@"SETTINGS_REREGISTER_BUTTON",
                                                                  @"Label for re-registration button.")
                                      accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"reregister")
                                                     selector:@selector(reregisterUser)
                                                        color:[UIColor ows_materialBlueColor]]];
        [section addItem:[self destructiveButtonItemWithTitle:NSLocalizedString(@"SETTINGS_DELETE_DATA_BUTTON",
                                                                  @"Label for 'delete data' button.")
                                      accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"delete_data")
                                                     selector:@selector(deleteUnregisterUserData)
                                                        color:[UIColor ows_destructiveRedColor]]];
    } else {
        [section
            addItem:[self destructiveButtonItemWithTitle:NSLocalizedString(@"SETTINGS_DELETE_ACCOUNT_BUTTON", @"")
                                 accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"delete_account")
                                                selector:@selector(unregisterUser)
                                                   color:[UIColor ows_destructiveRedColor]]];
    }

    [contents addSection:section];

    self.contents = contents;
}

- (OWSTableItem *)destructiveButtonItemWithTitle:(NSString *)title
                         accessibilityIdentifier:(NSString *)accessibilityIdentifier
                                        selector:(SEL)selector
                                           color:(UIColor *)color
{
    __weak AppSettingsViewController *weakSelf = self;
   return [OWSTableItem
        itemWithCustomCellBlock:^{
            UITableViewCell *cell = [OWSTableItem newCell];
            cell.preservesSuperviewLayoutMargins = YES;
            cell.contentView.preservesSuperviewLayoutMargins = YES;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            const CGFloat kButtonHeight = 40.f;
            OWSFlatButton *button = [OWSFlatButton buttonWithTitle:title
                                                              font:[OWSFlatButton fontForHeight:kButtonHeight]
                                                        titleColor:[UIColor whiteColor]
                                                   backgroundColor:color
                                                            target:weakSelf
                                                          selector:selector];
            [cell.contentView addSubview:button];
            [button autoSetDimension:ALDimensionHeight toSize:kButtonHeight];
            [button autoVCenterInSuperview];
            [button autoPinLeadingAndTrailingToSuperviewMargin];
            button.accessibilityIdentifier = accessibilityIdentifier;

            return cell;
        }
                customRowHeight:90.f
                    actionBlock:nil];
}

- (UITableViewCell *)profileHeaderCell
{
    UITableViewCell *cell = [OWSTableItem newCell];
    cell.preservesSuperviewLayoutMargins = YES;
    cell.contentView.preservesSuperviewLayoutMargins = YES;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UIImage *_Nullable localProfileAvatarImage = [OWSProfileManager.sharedManager localProfileAvatarImage];
    UIImage *avatarImage = (localProfileAvatarImage
            ?: [[[OWSContactAvatarBuilder alloc] initForLocalUserWithDiameter:kLargeAvatarSize] buildDefaultImage]);
    OWSAssertDebug(avatarImage);

    AvatarImageView *avatarView = [[AvatarImageView alloc] initWithImage:avatarImage];
    [cell.contentView addSubview:avatarView];
    [avatarView autoVCenterInSuperview];
    [avatarView autoPinLeadingToSuperviewMargin];
    [avatarView autoSetDimension:ALDimensionWidth toSize:kLargeAvatarSize];
    [avatarView autoSetDimension:ALDimensionHeight toSize:kLargeAvatarSize];

    if (!localProfileAvatarImage) {
        UIImageView *cameraImageView = [UIImageView new];
        [cameraImageView setTemplateImageName:@"camera-outline-24" tintColor:Theme.secondaryColor];
        [cell.contentView addSubview:cameraImageView];

        [cameraImageView autoSetDimensionsToSize:CGSizeMake(32, 32)];
        cameraImageView.contentMode = UIViewContentModeCenter;
        cameraImageView.backgroundColor = Theme.backgroundColor;
        cameraImageView.layer.cornerRadius = 16;
        cameraImageView.layer.shadowColor =
            [(Theme.isDarkThemeEnabled ? Theme.darkThemeOffBackgroundColor : Theme.primaryColor) CGColor];
        cameraImageView.layer.shadowOffset = CGSizeMake(1, 1);
        cameraImageView.layer.shadowOpacity = 0.5;
        cameraImageView.layer.shadowRadius = 4;

        [cameraImageView autoPinTrailingToEdgeOfView:avatarView];
        [cameraImageView autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:avatarView];
    }

    UIView *nameView = [UIView containerView];
    [cell.contentView addSubview:nameView];
    [nameView autoVCenterInSuperview];
    [nameView autoPinLeadingToTrailingEdgeOfView:avatarView offset:16.f];

    UILabel *titleLabel = [UILabel new];
    NSString *_Nullable localProfileName = [OWSProfileManager.sharedManager localProfileName];
    if (localProfileName.length > 0) {
        titleLabel.text = localProfileName;
        titleLabel.textColor = [Theme primaryColor];
        titleLabel.font = [UIFont ows_dynamicTypeTitle2Font];
    } else {
        titleLabel.text = NSLocalizedString(
            @"APP_SETTINGS_EDIT_PROFILE_NAME_PROMPT", @"Text prompting user to edit their profile name.");
        titleLabel.textColor = [UIColor ows_materialBlueColor];
        titleLabel.font = [UIFont ows_dynamicTypeHeadlineFont];
    }
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [nameView addSubview:titleLabel];
    [titleLabel autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [titleLabel autoPinWidthToSuperview];

    __block UIView *lastTitleView = titleLabel;
    const CGFloat kSubtitlePointSize = 12.f;
    void (^addSubtitle)(NSString *) = ^(NSString *subtitle) {
        UILabel *subtitleLabel = [UILabel new];
        subtitleLabel.textColor = Theme.secondaryColor;
        subtitleLabel.font = [UIFont ows_regularFontWithSize:kSubtitlePointSize];
        subtitleLabel.text = subtitle;
        subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [nameView addSubview:subtitleLabel];
        [subtitleLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:lastTitleView];
        [subtitleLabel autoPinLeadingToSuperviewMargin];
        lastTitleView = subtitleLabel;
    };

    addSubtitle(
        [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:[TSAccountManager localNumber]]);

    NSString *_Nullable username = [OWSProfileManager.sharedManager localUsername];
    if (username.length > 0) {
        addSubtitle([CommonFormats formatUsername:username]);
    }

    [lastTitleView autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    UIImage *disclosureImage = [UIImage imageNamed:(CurrentAppContext().isRTL ? @"NavBarBack" : @"NavBarBackRTL")];
    OWSAssertDebug(disclosureImage);
    UIImageView *disclosureButton =
        [[UIImageView alloc] initWithImage:[disclosureImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    disclosureButton.tintColor = [UIColor colorWithRGBHex:0xcccccc];
    [cell.contentView addSubview:disclosureButton];
    [disclosureButton autoVCenterInSuperview];
    [disclosureButton autoPinTrailingToSuperviewMargin];
    [disclosureButton autoPinLeadingToTrailingEdgeOfView:nameView offset:16.f];
    [disclosureButton setContentCompressionResistancePriority:(UILayoutPriorityDefaultHigh + 1)
                                                      forAxis:UILayoutConstraintAxisHorizontal];

    cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"profile");

    return cell;
}

- (void)showInviteFlow
{
    OWSInviteFlow *inviteFlow = [[OWSInviteFlow alloc] initWithPresentingViewController:self];
    self.inviteFlow = inviteFlow;
    [inviteFlow presentWithIsAnimated:YES completion:nil];
}

- (void)showPrivacy
{
    PrivacySettingsTableViewController *vc = [[PrivacySettingsTableViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showNotifications
{
    NotificationSettingsViewController *vc = [[NotificationSettingsViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showLinkedDevices
{
    OWSLinkedDevicesTableViewController *vc = [OWSLinkedDevicesTableViewController new];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showProfile
{
    [ProfileViewController presentForAppSettings:self.navigationController];
}

- (void)showAdvanced
{
    AdvancedSettingsTableViewController *vc = [[AdvancedSettingsTableViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showAbout
{
    AboutTableViewController *vc = [[AboutTableViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showBackup
{
    OWSBackupSettingsViewController *vc = [OWSBackupSettingsViewController new];
    [self.navigationController pushViewController:vc animated:YES];
}

#ifdef USE_DEBUG_UI
- (void)showDebugUI
{
    [DebugUITableViewController presentDebugUIFromViewController:self];
}
#endif

- (void)dismissWasPressed:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Unregister & Re-register

- (void)unregisterUser
{
    [self showDeleteAccountUI:YES];
}

- (void)deleteUnregisterUserData
{
    [self showDeleteAccountUI:NO];
}

- (void)showDeleteAccountUI:(BOOL)isRegistered
{
    __weak AppSettingsViewController *weakSelf = self;

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"CONFIRM_ACCOUNT_DESTRUCTION_TITLE", @"")
                                            message:NSLocalizedString(@"CONFIRM_ACCOUNT_DESTRUCTION_TEXT", @"")
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"PROCEED_BUTTON", @"")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
                                                [weakSelf deleteAccount:isRegistered];
                                            }]];
    [alert addAction:[OWSAlerts cancelAction]];

    [self presentAlert:alert];
}

- (void)deleteAccount:(BOOL)isRegistered
{
    if (isRegistered) {
        [ModalActivityIndicatorViewController
            presentFromViewController:self
                            canCancel:NO
                      backgroundBlock:^(ModalActivityIndicatorViewController *modalActivityIndicator) {
                          [TSAccountManager
                              unregisterTextSecureWithSuccess:^{
                                  [SignalApp resetAppData];
                              }
                              failure:^(NSError *error) {
                                  dispatch_async(dispatch_get_main_queue(), ^{
                                      [modalActivityIndicator dismissWithCompletion:^{
                                          [OWSAlerts
                                              showAlertWithTitle:NSLocalizedString(@"UNREGISTER_SIGNAL_FAIL", @"")];
                                      }];
                                  });
                              }];
                      }];
    } else {
        [SignalApp resetAppData];
    }
}

- (void)reregisterUser
{
    [RegistrationUtils showReregistrationUIFromViewController:self];
}

#pragma mark - Dark Theme

- (UIBarButtonItem *)darkThemeBarButton
{
    UIBarButtonItem *barButtonItem;
    if (Theme.isDarkThemeEnabled) {
        barButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ic_dark_theme_on"]
                                                         style:UIBarButtonItemStylePlain
                                                        target:self
                                                        action:@selector(didPressDisableDarkTheme:)];
    } else {
        barButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ic_dark_theme_off"]
                                                         style:UIBarButtonItemStylePlain
                                                        target:self
                                                        action:@selector(didPressEnableDarkTheme:)];
    }
    barButtonItem.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"dark_theme");
    return barButtonItem;
}

- (void)didPressEnableDarkTheme:(id)sender
{
    [Theme setIsDarkThemeEnabled:YES];
    [self updateRightBarButtonForTheme];
    [self updateTableContents];
}

- (void)didPressDisableDarkTheme:(id)sender
{
    [Theme setIsDarkThemeEnabled:NO];
    [self updateRightBarButtonForTheme];
    [self updateTableContents];
}

- (void)updateRightBarButtonForTheme
{
    self.navigationItem.rightBarButtonItem = [self darkThemeBarButton];
}

#pragma mark - Socket Status Notifications

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(socketStateDidChange)
                                                 name:kNSNotification_OWSWebSocketStateDidChange
                                               object:nil];
}

- (void)socketStateDidChange
{
    OWSAssertIsOnMainThread();

    [self updateTableContents];
}

@end
