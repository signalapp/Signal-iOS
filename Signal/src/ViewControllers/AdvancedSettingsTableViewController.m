//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AdvancedSettingsTableViewController.h"
#import "DebugLogger.h"
#import "Environment.h"
#import "PropertyListPreferences.h"
#import "PushManager.h"
#import "Signal-Swift.h"
#import "TSAccountManager.h"
#import "Pastelog.h"

NS_ASSUME_NONNULL_BEGIN

@interface AdvancedSettingsTableViewController ()

@property (nonatomic) UISwitch *enableLogSwitch;

@end

#pragma mark -

@implementation AdvancedSettingsTableViewController

- (void)loadView
{
    [super loadView];

    self.title = NSLocalizedString(@"SETTINGS_ADVANCED_TITLE", @"");
    
    self.enableLogSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [self.enableLogSwitch setOn:[PropertyListPreferences loggingIsEnabled]];
    [self.enableLogSwitch addTarget:self
                             action:@selector(didToggleEnableLogSwitch:)
                   forControlEvents:UIControlEventValueChanged];

    [self observeNotifications];

    [self updateTableContents];
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(socketStateDidChange)
                                                 name:kNSNotification_SocketManagerStateDidChange
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)socketStateDidChange
{
    OWSAssert([NSThread isMainThread]);

    [self updateTableContents];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak AdvancedSettingsTableViewController *weakSelf = self;

    OWSTableSection *loggingSection = [OWSTableSection new];
    loggingSection.headerTitle = NSLocalizedString(@"LOGGING_SECTION", nil);
    [loggingSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
        UITableViewCell *cell = [UITableViewCell new];
        cell.textLabel.text = NSLocalizedString(@"SETTINGS_ADVANCED_DEBUGLOG", @"");
        cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
        cell.textLabel.textColor = [UIColor blackColor];

        cell.accessoryView = self.enableLogSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
                                                      actionBlock:nil]];
    if (self.enableLogSwitch.isOn) {
        [loggingSection
            addItem:[OWSTableItem actionItemWithText:NSLocalizedString(@"SETTINGS_ADVANCED_SUBMIT_DEBUGLOG", @"")
                                         actionBlock:^{
                                             DDLogInfo(@"%@ Submitting debug logs", self.tag);
                                             [DDLog flushLog];
                                             [Pastelog submitLogs];
                                         }]];
    }

    [contents addSection:loggingSection];

    OWSTableSection *pushNotificationsSection = [OWSTableSection new];
    pushNotificationsSection.headerTitle
        = NSLocalizedString(@"PUSH_REGISTER_TITLE", @"Used in table section header and alert view title contexts");
    [pushNotificationsSection addItem:[OWSTableItem actionItemWithText:NSLocalizedString(@"REREGISTER_FOR_PUSH", nil)
                                                           actionBlock:^{
                                                               [weakSelf syncPushTokens];
                                                           }]];


    [contents addSection:pushNotificationsSection];

    self.contents = contents;
}

#pragma mark - Actions

- (void)syncPushTokens
{
    OWSSyncPushTokensJob *job =
        [[OWSSyncPushTokensJob alloc] initWithPushManager:[PushManager sharedManager]
                                           accountManager:[Environment getCurrent].accountManager
                                              preferences:[Environment preferences]
                                               showAlerts:YES];
    job.uploadOnlyIfStale = NO;
    [job run];
}

- (void)didToggleEnableLogSwitch:(UISwitch *)sender {
    if (!sender.isOn) {
        [[DebugLogger sharedLogger] wipeLogs];
        [[DebugLogger sharedLogger] disableFileLogging];
    } else {
        [[DebugLogger sharedLogger] enableFileLogging];
    }
    
    [PropertyListPreferences setLoggingEnabled:sender.isOn];

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

NS_ASSUME_NONNULL_END
