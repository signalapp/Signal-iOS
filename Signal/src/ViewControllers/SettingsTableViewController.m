//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SettingsTableViewController.h"
#import "AboutTableViewController.h"
#import "AdvancedSettingsTableViewController.h"
#import "DebugUITableViewController.h"
#import "Environment.h"
#import "NotificationSettingsViewController.h"
#import "OWSContactsManager.h"
#import "OWSLinkedDevicesTableViewController.h"
#import "PrivacySettingsTableViewController.h"
#import "PropertyListPreferences.h"
#import "PushManager.h"
#import "Signal-Swift.h"
#import "UIUtil.h"
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSSocketManager.h>

@interface SettingsTableViewController ()

@property (nonatomic, readonly) OWSContactsManager *contactsManager;

@end

#pragma mark -

@implementation SettingsTableViewController

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _contactsManager = [Environment getCurrent].contactsManager;

    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    _contactsManager = [Environment getCurrent].contactsManager;

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

    [self.navigationController.navigationBar setTranslucent:NO];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                      target:self
                                                      action:@selector(dismissWasPressed:)];

    [self observeNotifications];

    self.title = NSLocalizedString(@"SETTINGS_NAV_BAR_TITLE", @"Title for settings activity");
    
    [self updateTableContents];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self updateTableContents];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];
    OWSTableSection *section = [OWSTableSection new];

    __weak SettingsTableViewController *weakSelf = self;
    [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
        UITableViewCell *cell = [UITableViewCell new];

        UILabel *titleLabel = [UILabel new];
        titleLabel.font = [UIFont ows_mediumFontWithSize:20.f];
        titleLabel.textColor = [UIColor blackColor];
        titleLabel.text = NSLocalizedString(@"REGISTERED_NUMBER_TEXT", @"");
        titleLabel.textAlignment = NSTextAlignmentCenter;

        UILabel *subtitleLabel = [UILabel new];
        subtitleLabel.font = [UIFont ows_mediumFontWithSize:15.f];
        subtitleLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1.f];
        subtitleLabel.text =
            [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:[TSAccountManager localNumber]];
        subtitleLabel.textAlignment = NSTextAlignmentCenter;

        UIView *stack = [UIView new];
        [cell addSubview:stack];
        [stack autoCenterInSuperview];

        [stack addSubview:titleLabel];
        [stack addSubview:subtitleLabel];
        [titleLabel autoPinWidthToSuperview];
        [subtitleLabel autoPinWidthToSuperview];
        [titleLabel autoPinEdgeToSuperviewEdge:ALEdgeTop];
        [subtitleLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom];
        [subtitleLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:titleLabel];

        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
                                           customRowHeight:96.f
                                               actionBlock:nil]];

    if (OWSSignalService.sharedInstance.isCensorshipCircumventionActive) {
        [section
            addItem:[OWSTableItem disclosureItemWithText:
                                      NSLocalizedString(@"NETWORK_STATUS_CENSORSHIP_CIRCUMVENTION_ACTIVE",
                                          @"Indicates to the user that censorship circumvention has been activated.")
                                             actionBlock:^{
                                                 [weakSelf showAdvanced];
                                             }]];
    } else {
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            UITableViewCell *cell = [UITableViewCell new];
            cell.textLabel.text = NSLocalizedString(@"NETWORK_STATUS_HEADER", @"");
            cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
            cell.textLabel.textColor = [UIColor blackColor];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UILabel *accessoryLabel = [UILabel new];
            accessoryLabel.font = [UIFont ows_regularFontWithSize:18.f];
            switch ([TSSocketManager sharedManager].state) {
                case SocketManagerStateClosed:
                    accessoryLabel.text = NSLocalizedString(@"NETWORK_STATUS_OFFLINE", @"");
                    accessoryLabel.textColor = [UIColor ows_redColor];
                    break;
                case SocketManagerStateConnecting:
                    accessoryLabel.text = NSLocalizedString(@"NETWORK_STATUS_CONNECTING", @"");
                    accessoryLabel.textColor = [UIColor ows_yellowColor];
                    break;
                case SocketManagerStateOpen:
                    accessoryLabel.text = NSLocalizedString(@"NETWORK_STATUS_CONNECTED", @"");
                    accessoryLabel.textColor = [UIColor ows_greenColor];
                    break;
            }
            [accessoryLabel sizeToFit];
            cell.accessoryView = accessoryLabel;
            return cell;
        }
                                                   actionBlock:nil]];
    }
    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_INVITE_TITLE",
                                                              @"Settings table view cell label")
                                              actionBlock:^{
                                                  [weakSelf showInviteFlow];
                                              }]];
    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_PRIVACY_TITLE",
                                                              @"Settings table view cell label")
                                              actionBlock:^{
                                                  [weakSelf showPrivacy];
                                              }]];
    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_NOTIFICATIONS", nil)
                                              actionBlock:^{
                                                  [weakSelf showNotifications];
                                              }]];
    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"LINKED_DEVICES_TITLE",
                                                              @"Menu item and navbar title for the device manager")
                                              actionBlock:^{
                                                  [weakSelf showLinkedDevices];
                                              }]];
    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_ADVANCED_TITLE", @"")
                                              actionBlock:^{
                                                  [weakSelf showAdvanced];
                                              }]];
    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_ABOUT", @"")
                                              actionBlock:^{
                                                  [weakSelf showAbout];
                                              }]];

#ifdef DEBUG
    [section addItem:[OWSTableItem disclosureItemWithText:@"Debug UI"
                                              actionBlock:^{
                                                  [weakSelf showDebugUI];
                                              }]];
#endif

    [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
        UITableViewCell *cell = [UITableViewCell new];
        cell.preservesSuperviewLayoutMargins = YES;
        cell.contentView.preservesSuperviewLayoutMargins = YES;
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.backgroundColor = [UIColor ows_destructiveRedColor];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [button setTitle:NSLocalizedString(@"SETTINGS_DELETE_ACCOUNT_BUTTON", @"") forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont ows_mediumFontWithSize:18.f];
        button.titleLabel.textAlignment = NSTextAlignmentCenter;
        [cell.contentView addSubview:button];
        [button autoSetDimension:ALDimensionHeight toSize:50.f];
        [button autoVCenterInSuperview];
        [button autoPinLeadingToSuperView];
        [button autoPinTrailingToSuperView];
        [button addTarget:self action:@selector(unregisterUser) forControlEvents:UIControlEventTouchUpInside];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
                                           customRowHeight:100.f
                                               actionBlock:nil]];

    [contents addSection:section];
    
    self.contents = contents;
}

- (void)showInviteFlow
{
    OWSInviteFlow *inviteFlow =
        [[OWSInviteFlow alloc] initWithPresentingViewController:self contactsManager:self.contactsManager];
    [self presentViewController:inviteFlow.actionSheetController animated:YES completion:nil];
}

- (void)showPrivacy
{
    PrivacySettingsTableViewController *vc = [[PrivacySettingsTableViewController alloc] init];
    NSAssert(self.navigationController != nil, @"Navigation controller must not be nil");
    NSAssert(vc != nil, @"Privacy Settings View Controller must not be nil");
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showNotifications
{
    NotificationSettingsViewController *vc = [[NotificationSettingsViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showLinkedDevices
{
    OWSLinkedDevicesTableViewController *vc =
        [[UIStoryboard main] instantiateViewControllerWithIdentifier:@"OWSLinkedDevicesTableViewController"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showAdvanced
{
    AdvancedSettingsTableViewController *vc = [[AdvancedSettingsTableViewController alloc] init];
    NSAssert(self.navigationController != nil, @"Navigation controller must not be nil");
    NSAssert(vc != nil, @"Advanced Settings View Controller must not be nil");
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showAbout
{
    AboutTableViewController *vc = [[AboutTableViewController alloc] init];
    NSAssert(self.navigationController != nil, @"Navigation controller must not be nil");
    NSAssert(vc != nil, @"About View Controller must not be nil");
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showDebugUI
{
    [DebugUITableViewController presentDebugUIFromViewController:self];
}

- (void)dismissWasPressed:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table view data source

- (void)unregisterUser
{
    UIAlertController *alertController =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"CONFIRM_ACCOUNT_DESTRUCTION_TITLE", @"")
                                            message:NSLocalizedString(@"CONFIRM_ACCOUNT_DESTRUCTION_TEXT", @"")
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"PROCEED_BUTTON", @"")
                                                        style:UIAlertActionStyleDestructive
                                                      handler:^(UIAlertAction *action) {
                                                        [self proceedToUnregistration];
                                                      }]];
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                        style:UIAlertActionStyleCancel
                                                      handler:nil]];

    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)proceedToUnregistration {
    [TSAccountManager unregisterTextSecureWithSuccess:^{
        [Environment resetAppData];
    }
        failure:^(NSError *error) {
            [OWSAlerts showAlertWithTitle:NSLocalizedString(@"UNREGISTER_SIGNAL_FAIL", @"")];
        }];
}

#pragma mark - Socket Status Notifications

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(socketStateDidChange)
                                                 name:kNSNotification_SocketManagerStateDidChange
                                               object:nil];
}

- (void)socketStateDidChange {
    OWSAssert([NSThread isMainThread]);
    
    [self updateTableContents];
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
