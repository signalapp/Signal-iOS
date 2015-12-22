//
//  AdvancedSettingsTableViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 05/01/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "AdvancedSettingsTableViewController.h"

#import <PastelogKit/Pastelog.h>
#import "DebugLogger.h"
#import "Environment.h"
#import "PreferencesUtil.h"
#import "PushManager.h"
#import "TSAccountManager.h"


@interface AdvancedSettingsTableViewController ()

@property NSArray *sectionsArray;
@property (strong, nonatomic) UITableViewCell *enableLogCell;
@property (strong, nonatomic) UITableViewCell *submitLogCell;
@property (strong, nonatomic) UITableViewCell *registerPushCell;

@property (strong, nonatomic) UISwitch *enableLogSwitch;
@end

@implementation AdvancedSettingsTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (instancetype)init {
    self.sectionsArray =
        @[ NSLocalizedString(@"LOGGING_SECTION", nil), NSLocalizedString(@"PUSH_REGISTER_TITLE", nil) ];

    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (void)loadView {
    [super loadView];

    self.title = NSLocalizedString(@"SETTINGS_ADVANCED_TITLE", @"");

    // Enable Log
    self.enableLogCell                        = [[UITableViewCell alloc] init];
    self.enableLogCell.textLabel.text         = NSLocalizedString(@"SETTINGS_ADVANCED_DEBUGLOG", @"");
    self.enableLogCell.userInteractionEnabled = YES;

    self.enableLogSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [self.enableLogSwitch setOn:[Environment.preferences loggingIsEnabled]];
    [self.enableLogSwitch addTarget:self
                             action:@selector(didToggleSwitch:)
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
            return self.enableLogSwitch.isOn ? 2 : 1;
        case 1:
            return 1;
        default:
            return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self.sectionsArray objectAtIndex:(NSUInteger)section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        switch (indexPath.row) {
            case 0:
                return self.enableLogCell;
            case 1:
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
        __block failedPushRegistrationBlock failure = ^(NSError *error) {
          SignalAlertView(NSLocalizedString(@"PUSH_REGISTER_TITLE", nil), NSLocalizedString(@"REGISTRATION_BODY", nil));
        };

        [[PushManager sharedManager] requestPushTokenWithSuccess:^(NSString *pushToken, NSString *voipToken) {
          [TSAccountManager registerForPushNotifications:pushToken
                                               voipToken:voipToken
                                                 success:^{
                                                   SignalAlertView(NSLocalizedString(@"PUSH_REGISTER_TITLE", nil),
                                                                   NSLocalizedString(@"PUSH_REGISTER_SUCCESS", nil));
                                                 }
                                                 failure:failure];
        }
                                                         failure:failure];
    }
}

#pragma mark - Actions

- (void)didToggleSwitch:(UISwitch *)sender {
    if (!sender.isOn) {
        [[DebugLogger sharedLogger] wipeLogs];
        [[DebugLogger sharedLogger] disableFileLogging];
    } else {
        [[DebugLogger sharedLogger] enableFileLogging];
    }

    [Environment.preferences setLoggingEnabled:sender.isOn];
    [self.tableView reloadData];
}

@end
