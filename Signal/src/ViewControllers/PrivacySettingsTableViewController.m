//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "PrivacySettingsTableViewController.h"
#import "BlockListViewController.h"
#import "Environment.h"
#import "PropertyListPreferences.h"
#import "Signal-Swift.h"
#import "UIUtil.h"
#import <25519/Curve25519.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PrivacySettingsTableViewControllerSectionIndex) {
    PrivacySettingsTableViewControllerSectionIndexBlockList,
    PrivacySettingsTableViewControllerSectionIndexScreenSecurity,
    PrivacySettingsTableViewControllerSectionIndexCalling,
    PrivacySettingsTableViewControllerSectionIndexCallKit,
    PrivacySettingsTableViewControllerSectionIndexHistoryLog,
    PrivacySettingsTableViewControllerSectionIndexBlockOnIdentityChange,
    PrivacySettingsTableViewControllerSectionIndex_Count // meta section to track how many sections
};

@interface PrivacySettingsTableViewController ()

@property (nonatomic) UITableViewCell *blocklistCell;

@property (nonatomic) UITableViewCell *enableCallKitCell;
@property (nonatomic) UISwitch *enableCallKitSwitch;

@property (nonatomic) UITableViewCell *enableCallKitPrivacyCell;
@property (nonatomic) UISwitch *enableCallKitPrivacySwitch;

@property (nonatomic, strong) UITableViewCell *enableScreenSecurityCell;
@property (nonatomic, strong) UISwitch *enableScreenSecuritySwitch;

@property (nonatomic) UITableViewCell *callsHideIPAddressCell;
@property (nonatomic) UISwitch *callsHideIPAddressSwitch;

@property (nonatomic, strong) UITableViewCell *blockOnIdentityChangeCell;
@property (nonatomic, strong) UISwitch *blockOnIdentityChangeSwitch;

@property (nonatomic, strong) UITableViewCell *clearHistoryLogCell;

@end

@implementation PrivacySettingsTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];

    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

    dispatch_async(dispatch_get_main_queue(), ^{
        BlockListViewController *vc = [[BlockListViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    });
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)loadView {
    [super loadView];

    self.title = NSLocalizedString(@"SETTINGS_PRIVACY_TITLE", @"");

    // Block List
    self.blocklistCell = [UITableViewCell new];
    self.blocklistCell.textLabel.text
        = NSLocalizedString(@"SETTINGS_BLOCK_LIST_TITLE", @"Label for the block list section of the settings view");
    self.blocklistCell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    // CallKit opt-out
    self.enableCallKitCell = [UITableViewCell new];
    self.enableCallKitCell.textLabel.text = NSLocalizedString(@"SETTINGS_PRIVACY_CALLKIT_TITLE", @"Short table cell label");
    self.enableCallKitSwitch = [UISwitch new];
    [self.enableCallKitSwitch setOn:[[Environment getCurrent].preferences isCallKitEnabled]];
    [self.enableCallKitSwitch addTarget:self
                                 action:@selector(didToggleEnableCallKitSwitch:)
                       forControlEvents:UIControlEventValueChanged];
    self.enableCallKitCell.accessoryView = self.enableCallKitSwitch;

    // CallKit privacy
    self.enableCallKitPrivacyCell = [UITableViewCell new];
    self.enableCallKitPrivacyCell.textLabel.text = NSLocalizedString(@"SETTINGS_PRIVACY_CALLKIT_PRIVACY_TITLE", @"Label for 'CallKit privacy' preference");
    self.enableCallKitPrivacySwitch = [UISwitch new];
    [self.enableCallKitPrivacySwitch setOn:![[Environment getCurrent].preferences isCallKitPrivacyEnabled]];
    [self.enableCallKitPrivacySwitch addTarget:self
                                        action:@selector(didToggleEnableCallKitPrivacySwitch:)
                              forControlEvents:UIControlEventValueChanged];
    self.enableCallKitPrivacyCell.accessoryView = self.enableCallKitPrivacySwitch;

    // Enable Screen Security Cell
    self.enableScreenSecurityCell                = [[UITableViewCell alloc] init];
    self.enableScreenSecurityCell.textLabel.text = NSLocalizedString(@"SETTINGS_SCREEN_SECURITY", @"");
    self.enableScreenSecuritySwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.enableScreenSecurityCell.accessoryView          = self.enableScreenSecuritySwitch;
    self.enableScreenSecurityCell.userInteractionEnabled = YES;
    [self.enableScreenSecuritySwitch setOn:[Environment.preferences screenSecurityIsEnabled]];
    [self.enableScreenSecuritySwitch addTarget:self
                                        action:@selector(didToggleScreenSecuritySwitch:)
                              forControlEvents:UIControlEventValueChanged];

    // Allow calls to connect directly vs. using TURN exclusively
    self.callsHideIPAddressCell = [UITableViewCell new];
    self.callsHideIPAddressCell.textLabel.text
        = NSLocalizedString(@"SETTINGS_CALLING_HIDES_IP_ADDRESS_PREFERENCE_TITLE", @"Table cell label");
    self.callsHideIPAddressSwitch = [UISwitch new];
    self.callsHideIPAddressCell.accessoryView = self.callsHideIPAddressSwitch;
    [self.callsHideIPAddressSwitch setOn:[Environment.preferences doCallsHideIPAddress]];
    [self.callsHideIPAddressSwitch addTarget:self
                                      action:@selector(didToggleCallsHideIPAddressSwitch:)
                            forControlEvents:UIControlEventValueChanged];

    // Clear History Log Cell
    self.clearHistoryLogCell                = [[UITableViewCell alloc] init];
    self.clearHistoryLogCell.textLabel.text = NSLocalizedString(@"SETTINGS_CLEAR_HISTORY", @"");
    self.clearHistoryLogCell.accessoryType  = UITableViewCellAccessoryDisclosureIndicator;

    // Block Identity on KeyChange
    self.blockOnIdentityChangeCell = [UITableViewCell new];
    self.blockOnIdentityChangeCell.textLabel.text
        = NSLocalizedString(@"SETTINGS_BLOCK_ON_IDENTITY_CHANGE_TITLE", @"Table cell label");
    self.blockOnIdentityChangeSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.blockOnIdentityChangeCell.accessoryView = self.blockOnIdentityChangeSwitch;
    [self.blockOnIdentityChangeSwitch setOn:[Environment.preferences shouldBlockOnIdentityChange]];
    [self.blockOnIdentityChangeSwitch addTarget:self
                                         action:@selector(didToggleBlockOnIdentityChangeSwitch:)
                               forControlEvents:UIControlEventValueChanged];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return PrivacySettingsTableViewControllerSectionIndex_Count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case PrivacySettingsTableViewControllerSectionIndexBlockList:
            return 1;
        case PrivacySettingsTableViewControllerSectionIndexScreenSecurity:
            return 1;
        case PrivacySettingsTableViewControllerSectionIndexCalling:
            return 1;
        case PrivacySettingsTableViewControllerSectionIndexCallKit:
            if (![UIDevice currentDevice].supportsCallKit) {
                return 0;
            }
            return [Environment getCurrent].preferences.isCallKitEnabled ? 2 : 1;
        case PrivacySettingsTableViewControllerSectionIndexHistoryLog:
            return 1;
        case PrivacySettingsTableViewControllerSectionIndexBlockOnIdentityChange:
            return 1;
        default:
            return 0;
    }
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    switch (section) {
        case PrivacySettingsTableViewControllerSectionIndexScreenSecurity:
            return NSLocalizedString(@"SETTINGS_SCREEN_SECURITY_DETAIL", nil);
        case PrivacySettingsTableViewControllerSectionIndexCalling:
            return NSLocalizedString(@"SETTINGS_CALLING_HIDES_IP_ADDRESS_PREFERENCE_TITLE_DETAIL",
                @"User settings section footer, a detailed explanation");
        case PrivacySettingsTableViewControllerSectionIndexCallKit:
            return ([UIDevice currentDevice].supportsCallKit
                    ? NSLocalizedString(@"SETTINGS_SECTION_CALL_KIT_DESCRIPTION", @"Settings table section footer.")
                    : nil);
        case PrivacySettingsTableViewControllerSectionIndexBlockOnIdentityChange:
            return NSLocalizedString(
                @"SETTINGS_BLOCK_ON_IDENITY_CHANGE_DETAIL", @"User settings section footer, a detailed explanation");
        default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case PrivacySettingsTableViewControllerSectionIndexBlockList:
            return self.blocklistCell;
        case PrivacySettingsTableViewControllerSectionIndexScreenSecurity:
            return self.enableScreenSecurityCell;
        case PrivacySettingsTableViewControllerSectionIndexCalling:
            return self.callsHideIPAddressCell;
        case PrivacySettingsTableViewControllerSectionIndexCallKit:
            switch (indexPath.row) {
                case 0:
                    return self.enableCallKitCell;
                case 1:
                    return self.enableCallKitPrivacyCell;
            }
        case PrivacySettingsTableViewControllerSectionIndexHistoryLog:
            return self.clearHistoryLogCell;
        case PrivacySettingsTableViewControllerSectionIndexBlockOnIdentityChange:
            return self.blockOnIdentityChangeCell;
        default: {
            DDLogError(@"%@ Requested unknown table view cell for row at indexPath: %@", self.tag, indexPath);
            return [UITableViewCell new];
        }
    }
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case PrivacySettingsTableViewControllerSectionIndexScreenSecurity:
            return NSLocalizedString(@"SETTINGS_SECURITY_TITLE", @"Section header");
        case PrivacySettingsTableViewControllerSectionIndexCalling:
            return NSLocalizedString(@"SETTINGS_SECTION_TITLE_CALLING", @"settings topic header for table section");
        case PrivacySettingsTableViewControllerSectionIndexHistoryLog:
            return NSLocalizedString(@"SETTINGS_HISTORYLOG_TITLE", @"Section header");
        case PrivacySettingsTableViewControllerSectionIndexBlockOnIdentityChange:
            return NSLocalizedString(@"SETTINGS_PRIVACY_VERIFICATION_TITLE", @"Section header");
        default:
            return nil;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    switch (indexPath.section) {
        case PrivacySettingsTableViewControllerSectionIndexBlockList: {
            BlockListViewController *vc = [[BlockListViewController alloc] init];
            NSAssert(self.navigationController != nil, @"Navigation controller must not be nil");
            NSAssert(vc != nil, @"About View Controller must not be nil");
            [self.navigationController pushViewController:vc animated:YES];
            break;
        }
        case PrivacySettingsTableViewControllerSectionIndexHistoryLog: {
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil
                                                                                     message:NSLocalizedString(@"SETTINGS_DELETE_HISTORYLOG_CONFIRMATION", @"Alert message before user confirms clearing history")
                                                                              preferredStyle:UIAlertControllerStyleAlert];

            UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                                    style:UIAlertActionStyleCancel
                                                                  handler:nil];
            [alertController addAction:dismissAction];

            UIAlertAction *deleteAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"SETTINGS_DELETE_HISTORYLOG_CONFIRMATION_BUTTON", @"")
                                                                   style:UIAlertActionStyleDestructive
                                                                 handler:^(UIAlertAction * _Nonnull action) {
                                                                     [[TSStorageManager sharedManager] deleteThreadsAndMessages];
                                                                 }];
            [alertController addAction:deleteAction];

            [self presentViewController:alertController animated:true completion:nil];
            break;
        }
        default:
            break;
    }
}

#pragma mark - Toggle

- (void)didToggleScreenSecuritySwitch:(UISwitch *)sender
{
    BOOL enabled = self.enableScreenSecuritySwitch.isOn;
    DDLogInfo(@"%@ toggled screen security: %@", self.tag, enabled ? @"ON" : @"OFF");
    [Environment.preferences setScreenSecurity:enabled];
}

- (void)didToggleBlockOnIdentityChangeSwitch:(UISwitch *)sender
{
    BOOL enabled = self.blockOnIdentityChangeSwitch.isOn;
    DDLogInfo(@"%@ toggled blockOnIdentityChange: %@", self.tag, enabled ? @"ON" : @"OFF");
    [Environment.preferences setShouldBlockOnIdentityChange:enabled];
}

- (void)didToggleCallsHideIPAddressSwitch:(UISwitch *)sender
{
    BOOL enabled = sender.isOn;
    DDLogInfo(@"%@ toggled callsHideIPAddress: %@", self.tag, enabled ? @"ON" : @"OFF");
    [Environment.preferences setDoCallsHideIPAddress:enabled];
}

- (void)didToggleEnableCallKitSwitch:(UISwitch *)sender {
    DDLogInfo(@"%@ user toggled call kit preference: %@", self.tag, (sender.isOn ? @"ON" : @"OFF"));
    [[Environment getCurrent].preferences setIsCallKitEnabled:sender.isOn];
    // rebuild callUIAdapter since CallKit vs not changed.
    [[Environment getCurrent].callService createCallUIAdapter];
    [self.tableView reloadData];
}

- (void)didToggleEnableCallKitPrivacySwitch:(UISwitch *)sender {
    DDLogInfo(@"%@ user toggled call kit privacy preference: %@", self.tag, (sender.isOn ? @"ON" : @"OFF"));
    [[Environment getCurrent].preferences setIsCallKitPrivacyEnabled:!sender.isOn];
}

#pragma mark - Log util

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
