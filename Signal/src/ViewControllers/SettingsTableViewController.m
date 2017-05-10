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

//#define kProfileCellHeight 87.0f
//#define kStandardCellHeight 44.0f
//
//#define kNumberOfSections 4
//
//#define kRegisteredNumberRow 0
//#define kInviteRow 0
//#define kPrivacyRow 1
//#define kNotificationRow 2
//#define kLinkedDevices 3 // we don't actually use this, instead we segue via Interface Builder
//#define kAdvancedRow 4
//#define kAboutRow 5
//
//#define kNetworkRow 0
//#define kUnregisterRow 0
//
//typedef enum {
//    kRegisteredRows = 1,
//    kNetworkStatusRows = 1,
//    kGeneralRows = 6,
//    kUnregisterRows = 1,
//} kRowsForSection;
//
//typedef enum {
//    kRegisteredNumberSection = 0,
//    kNetworkStatusSection    = 1,
//    kGeneralSection          = 2,
//    kUnregisterSection       = 3,
//} kSection;

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

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.navigationItem setHidesBackButton:YES];

    [self.navigationController.navigationBar setTranslucent:NO];

////    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
//    self.registeredNumber.text =
//        [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:[TSAccountManager localNumber]];
//    self.registeredName.text = NSLocalizedString(@"REGISTERED_NUMBER_TEXT", @"");

    [self initializeObserver];

    self.title = NSLocalizedString(@"SETTINGS_NAV_BAR_TITLE", @"Title for settings activity");
    
//    self.networkStatusHeader.text = NSLocalizedString(@"NETWORK_STATUS_HEADER", @"");
//    self.privacyLabel.text = NSLocalizedString(@"SETTINGS_PRIVACY_TITLE", @"");
//    self.advancedLabel.text = NSLocalizedString(@"SETTINGS_ADVANCED_TITLE", @"");
//    self.aboutLabel.text = NSLocalizedString(@"SETTINGS_ABOUT", @"");
//    self.notificationsLabel.text = NSLocalizedString(@"SETTINGS_NOTIFICATIONS", nil);
//    self.linkedDevicesLabel.text
//        = NSLocalizedString(@"LINKED_DEVICES_TITLE", @"Menu item and navbar title for the device manager");
//    self.inviteLabel.text = NSLocalizedString(@"SETTINGS_INVITE_TITLE", @"Settings table view cell label");
//
//    [self.destroyAccountButton setTitle:NSLocalizedString(@"SETTINGS_DELETE_ACCOUNT_BUTTON", @"")
//                               forState:UIControlStateNormal];
    
    [self updateTableContents];
}

//- (void)viewWillAppear:(BOOL)animated
//{
//    [super viewWillAppear:animated];
//    // HACK to unselect rows when swiping back
//    // http://stackoverflow.com/questions/19379510/uitableviewcell-doesnt-get-deselected-when-swiping-back-quickly
//    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:animated];
//}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];
    OWSTableSection *section = [OWSTableSection new];
    
    // Find Non-Contacts by Phone Number
    [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
        UITableViewCell *cell = [UITableViewCell new];
        cell.textLabel.text = NSLocalizedString(
                                                @"NETWORK_STATUS_HEADER", @"");
        cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
        cell.textLabel.textColor = [UIColor blackColor];
        
        UILabel *accessoryLabel = [UILabel new];
        accessoryLabel.font = [UIFont ows_regularFontWithSize:18.f];
        switch ([TSSocketManager sharedManager].state) {
            case SocketManagerStateClosed:
                accessoryLabel.text      = NSLocalizedString(@"NETWORK_STATUS_OFFLINE", @"");
                accessoryLabel.textColor = [UIColor ows_redColor];
                break;
            case SocketManagerStateConnecting:
                accessoryLabel.text      = NSLocalizedString(@"NETWORK_STATUS_CONNECTING", @"");
                accessoryLabel.textColor = [UIColor ows_yellowColor];
                break;
            case SocketManagerStateOpen:
                accessoryLabel.text      = NSLocalizedString(@"NETWORK_STATUS_CONNECTED", @"");
                accessoryLabel.textColor = [UIColor ows_greenColor];
                break;
        }
        [accessoryLabel sizeToFit];
        cell.accessoryView = accessoryLabel;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
                                               actionBlock:nil]];
    
    [contents addSection:section];
    
    self.contents = contents;
}

#pragma mark - Table view data source

//- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
//    return kNumberOfSections;
//}
//
//- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
//    switch (section) {
//        case kRegisteredNumberSection:
//            return kRegisteredRows;
//        case kGeneralSection:
//            return kGeneralRows;
//        case kNetworkStatusSection:
//            return kNetworkStatusRows;
//        case kUnregisterSection:
//            return kUnregisterRows;
//        default:
//            return 0;
//    }
//}
//
//- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
//    [tableView deselectRowAtIndexPath:indexPath animated:YES];
//
//    switch (indexPath.section) {
//        case kGeneralSection: {
//            switch (indexPath.row) {
//                case kInviteRow: {
//                    OWSInviteFlow *inviteFlow =
//                        [[OWSInviteFlow alloc] initWithPresentingViewController:self
//                                                                contactsManager:self.contactsManager];
//                    [self presentViewController:inviteFlow.actionSheetController
//                                       animated:YES
//                                     completion:^{
//                                         [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
//                                     }];
//                    break;
//                }
//                case kPrivacyRow: {
//                    PrivacySettingsTableViewController *vc = [[PrivacySettingsTableViewController alloc] init];
//                    NSAssert(self.navigationController != nil, @"Navigation controller must not be nil");
//                    NSAssert(vc != nil, @"Privacy Settings View Controller must not be nil");
//                    [self.navigationController pushViewController:vc animated:YES];
//                    break;
//                }
//                case kNotificationRow: {
//                    NotificationSettingsViewController *vc = [[NotificationSettingsViewController alloc] init];
//                    [self.navigationController pushViewController:vc animated:YES];
//                    break;
//                }
//                case kAdvancedRow: {
//                    AdvancedSettingsTableViewController *vc = [[AdvancedSettingsTableViewController alloc] init];
//                    NSAssert(self.navigationController != nil, @"Navigation controller must not be nil");
//                    NSAssert(vc != nil, @"Advanced Settings View Controller must not be nil");
//                    [self.navigationController pushViewController:vc animated:YES];
//                    break;
//                }
//                case kAboutRow: {
//                    AboutTableViewController *vc = [[AboutTableViewController alloc] init];
//                    NSAssert(self.navigationController != nil, @"Navigation controller must not be nil");
//                    NSAssert(vc != nil, @"About View Controller must not be nil");
//                    [self.navigationController pushViewController:vc animated:YES];
//                    break;
//                }
//                default:
//                    DDLogError(@"%@ Unhandled row selected at index path: %@", self.tag, indexPath);
//                    break;
//            }
//
//            break;
//        }
//
//        case kNetworkStatusSection: {
//            break;
//        }
//
//        case kUnregisterSection: {
//            [self unregisterUser:nil];
//            break;
//        }
//
//        default:
//            break;
//    }
//}
//
//
//- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
//    switch (indexPath.section) {
//        case kNetworkStatusSection: {
//            return NO;
//        }
//
//        case kUnregisterSection: {
//            return NO;
//        }
//
//        default:
//            return YES;
//    }
//}


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
            [OWSAlerts showAlertWithTitle:NSLocalizedString(@"UNREGISTER_SIGNAL_FAIL", @"")];
        }];
}

//- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
//    if (indexPath.section == kNetworkStatusSection) {
//        [OWSAlerts showAlertWithTitle:NSLocalizedString(@"NETWORK_STATUS_HEADER", @"")
//                              message:NSLocalizedString(@"NETWORK_STATUS_TEXT", @"")];
//    }
//}

#pragma mark - Socket Status Notifications

- (void)initializeObserver {
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
