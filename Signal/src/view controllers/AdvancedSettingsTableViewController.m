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
#import <PastelogKit/Pastelog.h>
#import <PromiseKit/AnyPromise.h>

NS_ASSUME_NONNULL_BEGIN

@interface AdvancedSettingsTableViewController ()

@property (nonatomic) UITableViewCell *enableWebRTCCell;
@property (nonatomic) UITableViewCell *enableCallKitCell;
@property (nonatomic) UITableViewCell *enableLogCell;
@property (nonatomic) UITableViewCell *submitLogCell;
@property (nonatomic) UITableViewCell *registerPushCell;

@property (nonatomic) UISwitch *enableWebRTCSwitch;
@property (nonatomic) UISwitch *enableCallKitSwitch;
@property (nonatomic) UISwitch *enableLogSwitch;
@property (nonatomic, readonly) BOOL supportsCallKit;

@end

typedef NS_ENUM(NSInteger, AdvancedSettingsTableViewControllerSection) {
    AdvancedSettingsTableViewControllerSectionLogging,
    AdvancedSettingsTableViewControllerSectionCalling,
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

    // WebRTC
    self.enableWebRTCCell                        = [[UITableViewCell alloc] init];
    self.enableWebRTCCell.textLabel.text         = NSLocalizedString(@"SETTINGS_ADVANCED_WEBRTC",
                                                                     @"This setting is used to switch between new-style WebRTC calling and old-style RedPhone calling.");
    self.enableWebRTCCell.userInteractionEnabled = YES;
    self.enableWebRTCSwitch = [UISwitch new];
    [self.enableWebRTCSwitch setOn:[Environment.preferences isWebRTCEnabled]];
    [self.enableWebRTCSwitch addTarget:self
                                action:@selector(didToggleEnableWebRTCSwitch:)
                      forControlEvents:UIControlEventTouchUpInside];
    self.enableWebRTCCell.accessoryView = self.enableWebRTCSwitch;

    // CallKit opt-out
    self.enableCallKitCell = [UITableViewCell new];
    self.enableCallKitCell.textLabel.text = NSLocalizedString(@"SETTINGS_ADVANCED_CALLKIT_TITLE", @"Short table cell label");
    self.enableCallKitSwitch = [UISwitch new];
    [self.enableCallKitSwitch setOn:[[Environment getCurrent].preferences isCallKitEnabled]];
    [self.enableCallKitSwitch addTarget:self
                                 action:@selector(didToggleEnableCallKitSwitch:)
                       forControlEvents:UIControlEventTouchUpInside];
    self.enableCallKitCell.accessoryView = self.enableCallKitSwitch;
    
    // Enable Log
    self.enableLogCell                        = [[UITableViewCell alloc] init];
    self.enableLogCell.textLabel.text         = NSLocalizedString(@"SETTINGS_ADVANCED_DEBUGLOG", @"");
    self.enableLogCell.userInteractionEnabled = YES;
    self.enableLogSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [self.enableLogSwitch setOn:[Environment.preferences loggingIsEnabled]];
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
        case AdvancedSettingsTableViewControllerSectionCalling:
            return ([Environment.preferences isWebRTCEnabled] && self.supportsCallKit) ? 2 : 1;
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
        case AdvancedSettingsTableViewControllerSectionCalling:
            return NSLocalizedString(@"SETTINGS_SECTION_TITLE_CALLING", @"settings topic header for table section");
        case AdvancedSettingsTableViewControllerSectionPushNotifications:
            return NSLocalizedString(@"PUSH_REGISTER_TITLE", @"Used in table section header and alert view title contexts");
        default:
            return nil;
    }
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    AdvancedSettingsTableViewControllerSection settingsSection = (AdvancedSettingsTableViewControllerSection)section;
    switch (settingsSection) {
        case AdvancedSettingsTableViewControllerSectionCalling:
            // We only show the CallKit setting if WebRTC is enabled.
            if ([Environment.preferences isWebRTCEnabled] && [self supportsCallKit]) {
                return NSLocalizedString(@"SETTINGS_SECTION_CALL_KIT_DESCRIPTION", @"Settings table section footer.");
            }
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
        case AdvancedSettingsTableViewControllerSectionCalling:
            switch (indexPath.row) {
                case 0:
                    return self.enableWebRTCCell;
                case 1:
                    OWSAssert(self.supportsCallKit);
                    return self.enableCallKitCell;
                default:
                    // Unknown cell
                    OWSAssert(NO);
                    return nil;
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

- (void)didToggleEnableWebRTCSwitch:(UISwitch *)sender {
    static long long enableWebRTCRequestCounter = 0;
    long long enableWebRTCRequestId = ++enableWebRTCRequestCounter;

    __weak AdvancedSettingsTableViewController *weakSelf = self;
    BOOL isWebRTCEnabled = sender.isOn;
    DDLogInfo(@"%@ User set WebRTC calling to: %@", self.tag, (isWebRTCEnabled ? @"ON" : @"OFF"));
    TSUpdateAttributesRequest *request = [[TSUpdateAttributesRequest alloc] initWithUpdatedAttributes:isWebRTCEnabled];
    [[TSNetworkManager sharedManager] makeRequest:request
                                          success:^(NSURLSessionDataTask *task, id responseObject) {
                                              
                                              // Use the request id to ignore obsolete requests, e.g. if the
                                              // user repeatedly changes the setting faster than the requests
                                              // can complete.
                                              if (enableWebRTCRequestCounter != enableWebRTCRequestId) {
                                                  return;
                                              }
                                              
                                              // Only update the local setting if the request succeeds;
                                              // otherwise local and service state will fall out of sync
                                              // with every network failure.
                                              [Environment.preferences setIsWebRTCEnabled:isWebRTCEnabled];
                                              
                                              [weakSelf.tableView reloadData];
                                          }
                                          failure:^(NSURLSessionDataTask *task, NSError *error) {
                                              DDLogError(@"Updating attributes failed with error: %@", error.description);
                                              
                                              AdvancedSettingsTableViewController *strongSelf = weakSelf;
                                              // Use the request id to ignore obsolete requests, e.g. if the
                                              // user repeatedly changes the setting faster than the requests
                                              // can complete.
                                              if (!strongSelf ||
                                                  enableWebRTCRequestCounter != enableWebRTCRequestId) {
                                                  return;
                                              }
                                              
                                              // Restore switch to previous state.
                                              [strongSelf.enableLogSwitch setOn:!isWebRTCEnabled];
                                              
                                              // Alert.
                                              SignalAlertView(NSLocalizedString(@"SETTINGS_ADVANCED_WEBRTC_FAILED_TITLE",
                                                                                @"The title of the alert shown when updates to the WebRTC property fail."),
                                                              NSLocalizedString(@"SETTINGS_ADVANCED_WEBRTC_FAILED_MESSAGE",
                                                                                @"The message of the alert shown when updates to the WebRTC property fail."));
                                          }];
}

- (void)didToggleEnableLogSwitch:(UISwitch *)sender {
    if (!sender.isOn) {
        [[DebugLogger sharedLogger] wipeLogs];
        [[DebugLogger sharedLogger] disableFileLogging];
    } else {
        [[DebugLogger sharedLogger] enableFileLogging];
    }
    
    [Environment.preferences setLoggingEnabled:sender.isOn];
    [self.tableView reloadData];
}

- (void)didToggleEnableCallKitSwitch:(UISwitch *)sender {
    DDLogInfo(@"%@ user toggled call kit preference: %@", self.tag, (sender.isOn ? @"ON" : @"OFF"));
    [[Environment getCurrent].preferences setIsCallKitEnabled:sender.isOn];
    [[Environment getCurrent].callService createCallUIAdapter];
}

#pragma mark - Util

- (BOOL)supportsCallKit
{
    return SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(10, 0);
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
