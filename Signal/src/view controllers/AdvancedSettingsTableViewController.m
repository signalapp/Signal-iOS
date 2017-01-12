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
#import <PastelogKit/Pastelog.h>
#import <PromiseKit/AnyPromise.h>

NS_ASSUME_NONNULL_BEGIN

@interface AdvancedSettingsTableViewController ()

@property NSArray *sectionsArray;

@property (nonatomic) UITableViewCell *enableWebRTCCell;
@property (nonatomic) UITableViewCell *enableLogCell;
@property (nonatomic) UITableViewCell *submitLogCell;
@property (nonatomic) UITableViewCell *registerPushCell;

@property (nonatomic) UISwitch *enableWebRTCSwitch;
@property (nonatomic) UISwitch *enableLogSwitch;

@end

@implementation AdvancedSettingsTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (instancetype)init {
    self.sectionsArray = @[
        NSLocalizedString(@"LOGGING_SECTION", nil),
        NSLocalizedString(@"PUSH_REGISTER_TITLE", @"Used in table section header and alert view title contexts")
    ];

    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)loadView {
    [super loadView];

    self.title = NSLocalizedString(@"SETTINGS_ADVANCED_TITLE", @"");
    
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
    return (NSInteger)[self.sectionsArray count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return 1 + (self.enableLogSwitch.isOn ? 2 : 1);
        case 1:
            return 1;
        default:
            return 0;
    }
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return [self.sectionsArray objectAtIndex:(NSUInteger)section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        switch (indexPath.row) {
            case 0:
                return self.enableWebRTCCell;
            case 1:
                return self.enableLogCell;
            case 2:
                return self.enableLogSwitch.isOn ? self.submitLogCell : self.registerPushCell;
        }
    } else {
        return self.registerPushCell;
    }

    NSAssert(false, @"No Cell configured");

    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if ([tableView cellForRowAtIndexPath:indexPath] == self.submitLogCell) {
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
