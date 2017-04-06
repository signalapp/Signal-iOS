//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SettingsTableViewController.h"
#import "Environment.h"
#import "PropertyListPreferences.h"
#import "TSAccountManager.h"
#import "UIUtil.h"
#import "TSSocketManager.h"
#import "AboutTableViewController.h"
#import "AdvancedSettingsTableViewController.h"
#import "NotificationSettingsViewController.h"
#import "OWSContactsManager.h"
#import "PrivacySettingsTableViewController.h"
#import "PushManager.h"
#import "Signal-Swift.h"

#define kProfileCellHeight 87.0f
#define kStandardCellHeight 44.0f

#define kNumberOfSections 4

#define kRegisteredNumberRow 0
#define kInviteRow 0
#define kPrivacyRow 1
#define kNotificationRow 2
#define kLinkedDevices 3 // we don't actually use this, instead we segue via Interface Builder
#define kAdvancedRow 4
#define kAboutRow 5

#define kNetworkRow 0
#define kUnregisterRow 0

typedef enum {
    kRegisteredRows = 1,
    kNetworkStatusRows = 1,
    kGeneralRows = 6,
    kUnregisterRows = 1,
} kRowsForSection;

typedef enum {
    kRegisteredNumberSection = 0,
    kNetworkStatusSection    = 1,
    kGeneralSection          = 2,
    kUnregisterSection       = 3,
} kSection;

@interface SettingsTableViewController () <UIAlertViewDelegate>

@property (nonatomic, readonly) OWSContactsManager *contactsManager;

@end

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

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.navigationItem setHidesBackButton:YES];

    [self.navigationController.navigationBar setTranslucent:NO];

    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    self.registeredNumber.text =
        [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:[TSAccountManager localNumber]];
    self.registeredName.text = NSLocalizedString(@"REGISTERED_NUMBER_TEXT", @"");

    [self initializeObserver];
    [TSSocketManager sendNotification];

    self.title = NSLocalizedString(@"SETTINGS_NAV_BAR_TITLE", @"Title for settings activity");
    self.networkStatusHeader.text = NSLocalizedString(@"NETWORK_STATUS_HEADER", @"");
    self.privacyLabel.text = NSLocalizedString(@"SETTINGS_PRIVACY_TITLE", @"");
    self.advancedLabel.text = NSLocalizedString(@"SETTINGS_ADVANCED_TITLE", @"");
    self.aboutLabel.text = NSLocalizedString(@"SETTINGS_ABOUT", @"");
    self.notificationsLabel.text = NSLocalizedString(@"SETTINGS_NOTIFICATIONS", nil);
    self.linkedDevicesLabel.text
        = NSLocalizedString(@"LINKED_DEVICES_TITLE", @"Menu item and navbar title for the device manager");
    self.inviteLabel.text = NSLocalizedString(@"SETTINGS_INVITE_TITLE", @"Settings table view cell label");

    [self.destroyAccountButton setTitle:NSLocalizedString(@"SETTINGS_DELETE_ACCOUNT_BUTTON", @"")
                               forState:UIControlStateNormal];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    // HACK to unselect rows when swiping back
    // http://stackoverflow.com/questions/19379510/uitableviewcell-doesnt-get-deselected-when-swiping-back-quickly
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:animated];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SocketOpenedNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SocketClosedNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SocketConnectingNotification object:nil];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return kNumberOfSections;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case kRegisteredNumberSection:
            return kRegisteredRows;
        case kGeneralSection:
            return kGeneralRows;
        case kNetworkStatusSection:
            return kNetworkStatusRows;
        case kUnregisterSection:
            return kUnregisterRows;
        default:
            return 0;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    switch (indexPath.section) {
        case kGeneralSection: {
            switch (indexPath.row) {
                case kInviteRow: {
                    OWSInviteFlow *inviteFlow =
                        [[OWSInviteFlow alloc] initWithPresentingViewController:self
                                                                contactsManager:self.contactsManager];
                    [self presentViewController:inviteFlow.actionSheetController
                                       animated:YES
                                     completion:^{
                                         [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
                                     }];
                    break;
                }
                case kPrivacyRow: {
                    PrivacySettingsTableViewController *vc = [[PrivacySettingsTableViewController alloc] init];
                    NSAssert(self.navigationController != nil, @"Navigation controller must not be nil");
                    NSAssert(vc != nil, @"Privacy Settings View Controller must not be nil");
                    [self.navigationController pushViewController:vc animated:YES];
                    break;
                }
                case kNotificationRow: {
                    NotificationSettingsViewController *vc = [[NotificationSettingsViewController alloc] init];
                    [self.navigationController pushViewController:vc animated:YES];
                    break;
                }
                case kAdvancedRow: {
                    AdvancedSettingsTableViewController *vc = [[AdvancedSettingsTableViewController alloc] init];
                    NSAssert(self.navigationController != nil, @"Navigation controller must not be nil");
                    NSAssert(vc != nil, @"Advanced Settings View Controller must not be nil");
                    [self.navigationController pushViewController:vc animated:YES];
                    break;
                }
                case kAboutRow: {
                    AboutTableViewController *vc = [[AboutTableViewController alloc] init];
                    NSAssert(self.navigationController != nil, @"Navigation controller must not be nil");
                    NSAssert(vc != nil, @"About View Controller must not be nil");
                    [self.navigationController pushViewController:vc animated:YES];
                    break;
                }
                default:
                    DDLogError(@"%@ Unhandled row selected at index path: %@", self.tag, indexPath);
                    break;
            }

            break;
        }

        case kNetworkStatusSection: {
            break;
        }

        case kUnregisterSection: {
            [self unregisterUser:nil];
            break;
        }

        default:
            break;
    }
}


- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case kNetworkStatusSection: {
            return NO;
        }

        case kUnregisterSection: {
            return NO;
        }

        default:
            return YES;
    }
}


- (IBAction)unregisterUser:(id)sender {
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
          SignalAlertView(NSLocalizedString(@"UNREGISTER_SIGNAL_FAIL", @""), @"");
        }];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kNetworkStatusSection) {
        UIAlertView *info = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"NETWORK_STATUS_HEADER", @"")
                                                       message:NSLocalizedString(@"NETWORK_STATUS_TEXT", @"")
                                                      delegate:self
                                             cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                             otherButtonTitles:nil];
        [info show];
    }
}

#pragma mark - Socket Status Notifications

- (void)initializeObserver {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(socketDidOpen)
                                                 name:SocketOpenedNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(socketDidClose)
                                                 name:SocketClosedNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(socketIsConnecting)
                                                 name:SocketConnectingNotification
                                               object:nil];
}

- (void)socketDidOpen {
    self.networkStatusLabel.text      = NSLocalizedString(@"NETWORK_STATUS_CONNECTED", @"");
    self.networkStatusLabel.textColor = [UIColor ows_greenColor];
}

- (void)socketDidClose {
    self.networkStatusLabel.text      = NSLocalizedString(@"NETWORK_STATUS_OFFLINE", @"");
    self.networkStatusLabel.textColor = [UIColor ows_redColor];
}

- (void)socketIsConnecting {
    self.networkStatusLabel.text      = NSLocalizedString(@"NETWORK_STATUS_CONNECTING", @"");
    self.networkStatusLabel.textColor = [UIColor ows_yellowColor];
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
