//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AdvancedSettingsTableViewController.h"
#import "DebugLogger.h"
#import "Environment.h"
#import "PropertyListPreferences.h"
#import "PushManager.h"
#import "RPAccountManager.h"
#import "Signal-Swift.h"
#import "TSAccountManager.h"
#import "UIViewController+OWS.h"
#import "Pastelog.h"
#import <PromiseKit/AnyPromise.h>

NS_ASSUME_NONNULL_BEGIN

@interface AdvancedSettingsTableViewController ()

@property (nonatomic) UITableViewCell *enableLogCell;
@property (nonatomic) UITableViewCell *submitLogCell;
@property (nonatomic) UITableViewCell *registerPushCell;

@property (nonatomic) UISwitch *enableLogSwitch;
@property (nonatomic, readonly) BOOL supportsCallKit;

@end

typedef NS_ENUM(NSInteger, AdvancedSettingsTableViewControllerSection) {
    AdvancedSettingsTableViewControllerSectionLogging,
    AdvancedSettingsTableViewControllerSectionPushNotifications,
    AdvancedSettingsTableViewControllerSection_Count // meta section
};

@implementation AdvancedSettingsTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (instancetype)init
{
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)loadView
{
    [super loadView];

    self.title = NSLocalizedString(@"SETTINGS_ADVANCED_TITLE", @"");
    
    [self useOWSBackButton];
    
    // Enable Log
    self.enableLogCell                        = [[UITableViewCell alloc] init];
    self.enableLogCell.textLabel.text         = NSLocalizedString(@"SETTINGS_ADVANCED_DEBUGLOG", @"");
    self.enableLogCell.userInteractionEnabled = YES;
    self.enableLogSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [self.enableLogSwitch setOn:[PropertyListPreferences loggingIsEnabled]];
    [self.enableLogSwitch addTarget:self
                             action:@selector(didToggleEnableLogSwitch:)
                   forControlEvents:UIControlEventTouchUpInside];
    self.enableLogCell.accessoryView = self.enableLogSwitch;

    // Send Log
    self.submitLogCell                = [[UITableViewCell alloc] init];
    self.submitLogCell.textLabel.text = NSLocalizedString(@"SETTINGS_ADVANCED_SUBMIT_DEBUGLOG", @"");

    self.registerPushCell                = [[UITableViewCell alloc] init];
    self.registerPushCell.textLabel.text = NSLocalizedString(@"REREGISTER_FOR_PUSH", nil);
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return AdvancedSettingsTableViewControllerSection_Count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {

    AdvancedSettingsTableViewControllerSection settingsSection = (AdvancedSettingsTableViewControllerSection)section;
    switch (settingsSection) {
        case AdvancedSettingsTableViewControllerSectionLogging:
            return self.enableLogSwitch.isOn ? 2 : 1;
        case AdvancedSettingsTableViewControllerSectionPushNotifications:
            return 1;
        default:
            return 0;
    }
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    AdvancedSettingsTableViewControllerSection settingsSection = (AdvancedSettingsTableViewControllerSection)section;
    switch (settingsSection) {
        case AdvancedSettingsTableViewControllerSectionLogging:
            return NSLocalizedString(@"LOGGING_SECTION", nil);
        case AdvancedSettingsTableViewControllerSectionPushNotifications:
            return NSLocalizedString(@"PUSH_REGISTER_TITLE", @"Used in table section header and alert view title contexts");
        default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    AdvancedSettingsTableViewControllerSection settingsSection = (AdvancedSettingsTableViewControllerSection)indexPath.section;
    switch (settingsSection) {
        case AdvancedSettingsTableViewControllerSectionLogging:
            switch (indexPath.row) {
                case 0:
                    return self.enableLogCell;
                case 1:
                    OWSAssert(self.enableLogSwitch.isOn);
                    return self.submitLogCell;
            }
        case AdvancedSettingsTableViewControllerSectionPushNotifications:
            return self.registerPushCell;
        default:
            // Unknown section
            OWSAssert(NO);
            return nil;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if ([tableView cellForRowAtIndexPath:indexPath] == self.submitLogCell) {
        [DDLog flushLog];
        [Pastelog submitLogs];
    } else if ([tableView cellForRowAtIndexPath:indexPath] == self.registerPushCell) {
        OWSSyncPushTokensJob *syncJob =
            [[OWSSyncPushTokensJob alloc] initWithPushManager:[PushManager sharedManager]
                                               accountManager:[Environment getCurrent].accountManager
                                                  preferences:[Environment preferences]];
        syncJob.uploadOnlyIfStale = NO;
        [syncJob run]
            .then(^{
                SignalAlertView(NSLocalizedString(@"PUSH_REGISTER_SUCCESS", @"Alert title"), nil);
            })
            .catch(^(NSError *error) {
                SignalAlertView(NSLocalizedString(@"REGISTRATION_BODY", @"Alert title"), error.localizedDescription);
            });

    } else {
        DDLogDebug(@"%@ Ignoring cell selection at indexPath: %@", self.tag, indexPath);
    }
}

#pragma mark - Actions

- (void)didToggleEnableLogSwitch:(UISwitch *)sender {
    if (!sender.isOn) {
        [[DebugLogger sharedLogger] wipeLogs];
        [[DebugLogger sharedLogger] disableFileLogging];
    } else {
        [[DebugLogger sharedLogger] enableFileLogging];
    }
    
    [PropertyListPreferences setLoggingEnabled:sender.isOn];
    [self.tableView reloadData];
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

NS_ASSUME_NONNULL_END
