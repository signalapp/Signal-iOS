//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "PrivacySettingsTableViewController.h"

#import "Environment.h"
#import "PropertyListPreferences.h"
#import "UIUtil.h"
#import "UIViewController+OWS.h"
#import "Signal-Swift.h"
#import <25519/Curve25519.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PrivacySettingsTableViewControllerSectionIndex) {
    PrivacySettingsTableViewControllerSectionIndexScreenSecurity,
    PrivacySettingsTableViewControllerSectionIndexCalling,
    PrivacySettingsTableViewControllerSectionIndexCallKitEnabled,
    PrivacySettingsTableViewControllerSectionIndexCallKitPrivacy,
    PrivacySettingsTableViewControllerSectionIndexHistoryLog,
    PrivacySettingsTableViewControllerSectionIndexBlockOnIdentityChange,
    PrivacySettingsTableViewControllerSectionIndex_Count // meta section to track how many sections
};

@interface PrivacySettingsTableViewController ()

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
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)loadView {
    [super loadView];

    self.title = NSLocalizedString(@"SETTINGS_PRIVACY_TITLE", @"");

    [self useOWSBackButton];

    // CallKit opt-out
    self.enableCallKitCell = [UITableViewCell new];
    self.enableCallKitCell.textLabel.text = NSLocalizedString(@"SETTINGS_PRIVACY_CALLKIT_TITLE", @"Short table cell label");
    self.enableCallKitSwitch = [UISwitch new];
    [self.enableCallKitSwitch setOn:[[Environment getCurrent].preferences isCallKitEnabled]];
    [self.enableCallKitSwitch addTarget:self
                                 action:@selector(didToggleEnableCallKitSwitch:)
                       forControlEvents:UIControlEventTouchUpInside];
    self.enableCallKitCell.accessoryView = self.enableCallKitSwitch;

    // CallKit privacy
    self.enableCallKitPrivacyCell = [UITableViewCell new];
    self.enableCallKitPrivacyCell.textLabel.text = NSLocalizedString(@"SETTINGS_PRIVACY_CALLKIT_PRIVACY_TITLE", @"Label for 'CallKit privacy' preference");
    self.enableCallKitPrivacySwitch = [UISwitch new];
    [self.enableCallKitPrivacySwitch setOn:![[Environment getCurrent].preferences isCallKitPrivacyEnabled]];
    [self.enableCallKitPrivacySwitch addTarget:self
                                        action:@selector(didToggleEnableCallKitPrivacySwitch:)
                              forControlEvents:UIControlEventTouchUpInside];
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
                              forControlEvents:UIControlEventTouchUpInside];

    // Allow calls to connect directly vs. using TURN exclusively
    self.callsHideIPAddressCell = [UITableViewCell new];
    self.callsHideIPAddressCell.textLabel.text
        = NSLocalizedString(@"SETTINGS_CALLING_HIDES_IP_ADDRESS_PREFERENCE_TITLE", @"Table cell label");
    self.callsHideIPAddressSwitch = [UISwitch new];
    self.callsHideIPAddressCell.accessoryView = self.callsHideIPAddressSwitch;
    [self.callsHideIPAddressSwitch setOn:[Environment.preferences doCallsHideIPAddress]];
    [self.callsHideIPAddressSwitch addTarget:self
                                      action:@selector(didToggleCallsHideIPAddressSwitch:)
                            forControlEvents:UIControlEventTouchUpInside];

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
                               forControlEvents:UIControlEventTouchUpInside];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return PrivacySettingsTableViewControllerSectionIndex_Count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case PrivacySettingsTableViewControllerSectionIndexScreenSecurity:
            return 1;
        case PrivacySettingsTableViewControllerSectionIndexCalling:
            return 1;
        case PrivacySettingsTableViewControllerSectionIndexCallKitEnabled:
            return self.supportsCallKit ? 1 : 0;
        case PrivacySettingsTableViewControllerSectionIndexCallKitPrivacy:
            return (self.supportsCallKit && [[Environment getCurrent].preferences isCallKitEnabled]) ? 1 : 0;
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
        case PrivacySettingsTableViewControllerSectionIndexCallKitEnabled:
            return NSLocalizedString(@"SETTINGS_SECTION_CALL_KIT_DESCRIPTION", @"Settings table section footer.");
        case PrivacySettingsTableViewControllerSectionIndexCallKitPrivacy:
            return NSLocalizedString(@"SETTINGS_SECTION_CALL_KIT_PRIVACY_DESCRIPTION",
                                     @"Explanation of the 'CallKit Privacy` preference.");
        case PrivacySettingsTableViewControllerSectionIndexBlockOnIdentityChange:
            return NSLocalizedString(
                @"SETTINGS_BLOCK_ON_IDENITY_CHANGE_DETAIL", @"User settings section footer, a detailed explanation");
        default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case PrivacySettingsTableViewControllerSectionIndexScreenSecurity:
            return self.enableScreenSecurityCell;
        case PrivacySettingsTableViewControllerSectionIndexCalling:
            return self.callsHideIPAddressCell;
        case PrivacySettingsTableViewControllerSectionIndexCallKitEnabled:
            return self.enableCallKitCell;
        case PrivacySettingsTableViewControllerSectionIndexCallKitPrivacy:
            return self.enableCallKitPrivacyCell;
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
    [[Environment getCurrent].callService createCallUIAdapter];
}

- (void)didToggleEnableCallKitPrivacySwitch:(UISwitch *)sender {
    DDLogInfo(@"%@ user toggled call kit privacy preference: %@", self.tag, (sender.isOn ? @"ON" : @"OFF"));
    [[Environment getCurrent].preferences setIsCallKitPrivacyEnabled:!sender.isOn];
}

#pragma mark - Util

- (BOOL)supportsCallKit
{
    return SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(10, 0);
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
