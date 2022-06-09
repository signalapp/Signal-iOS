//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "PrivacySettingsTableViewController.h"

#import "Session-Swift.h"
#import <SignalCoreKit/NSString+OWS.h>

#import <SignalUtilitiesKit/UIColor+OWS.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import <SessionUtilitiesKit/NSString+SSK.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const kSealedSenderInfoURL = @"https://signal.org/blog/sealed-sender/";

@implementation PrivacySettingsTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self observeNotifications];

    [self updateTableContents];
    
    [LKViewControllerUtilities setUpDefaultSessionStyleForVC:self withTitle:NSLocalizedString(@"vc_privacy_settings_title", @"") customBackButton:NO];
    self.tableView.backgroundColor = UIColor.clearColor;
    
    if (self.shouldShowCloseButton) {
        UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"X"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(close:)];
        [[self navigationItem] setLeftBarButtonItem:closeButton];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [self updateTableContents];
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenLockDidChange:)
                                                 name:OWSScreenLock.ScreenLockDidChange
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak PrivacySettingsTableViewController *weakSelf = self;
    
    OWSTableSection *readReceiptsSection = [OWSTableSection new];
    readReceiptsSection.headerTitle
        = NSLocalizedString(@"SETTINGS_READ_RECEIPT", @"Label for the 'read receipts' setting.");
    readReceiptsSection.footerTitle = NSLocalizedString(
        @"SETTINGS_READ_RECEIPTS_SECTION_FOOTER", @"An explanation of the 'read receipts' setting.");
    [readReceiptsSection
        addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"SETTINGS_READ_RECEIPT",
                                                     @"Label for the 'read receipts' setting.")
                    accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"read_receipts"]
                    isOnBlock:^{
                        return [SMKPreferences areReadReceiptsEnabled];
                    }
                    isEnabledBlock:^{
                        return YES;
                    }
                    target:weakSelf
                    selector:@selector(didToggleReadReceiptsSwitch:)]];
    [contents addSection:readReceiptsSection];

    OWSTableSection *typingIndicatorsSection = [OWSTableSection new];
    typingIndicatorsSection.headerTitle
        = NSLocalizedString(@"SETTINGS_TYPING_INDICATORS", @"Label for the 'typing indicators' setting.");
    typingIndicatorsSection.footerTitle = NSLocalizedString(@"See and share when messages are being typed (applies to all sessions).", @"");
    [typingIndicatorsSection
        addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"SETTINGS_TYPING_INDICATORS",
                                                     @"Label for the 'typing indicators' setting.")
                    accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"typing_indicators"]
                    isOnBlock:^{
                        return [SMKPreferences areTypingIndicatorsEnabled];
                    }
                    isEnabledBlock:^{
                        return YES;
                    }
                    target:weakSelf
                    selector:@selector(didToggleTypingIndicatorsSwitch:)]];
    [contents addSection:typingIndicatorsSection];

    OWSTableSection *screenLockSection = [OWSTableSection new];
    screenLockSection.headerTitle = NSLocalizedString(
        @"SETTINGS_SCREEN_LOCK_SECTION_TITLE", @"Title for the 'screen lock' section of the privacy settings.");
    screenLockSection.footerTitle = NSLocalizedString(@"Require Touch ID, Face ID or your device passcode to unlock Session’s screen. You can still receive notifications when Screen Lock is enabled. Use Session’s notification settings to customise the information displayed in notifications.", @"");
    [screenLockSection
        addItem:[OWSTableItem
                    switchItemWithText:NSLocalizedString(@"SETTINGS_SCREEN_LOCK_SWITCH_LABEL",
                                           @"Label for the 'enable screen lock' switch of the privacy settings.")
                    accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"screenlock"]
                    isOnBlock:^{
                        return [OWSScreenLock.sharedManager isScreenLockEnabled];
                    }
                    isEnabledBlock:^{
                        return YES;
                    }
                    target:self
                    selector:@selector(isScreenLockEnabledDidChange:)]];
    [contents addSection:screenLockSection];

    if (OWSScreenLock.sharedManager.isScreenLockEnabled) {
        OWSTableSection *screenLockTimeoutSection = [OWSTableSection new];
        uint32_t screenLockTimeout = (uint32_t)round(OWSScreenLock.sharedManager.screenLockTimeout);
        NSString *screenLockTimeoutString = [self formatScreenLockTimeout:screenLockTimeout useShortFormat:YES];
        [screenLockTimeoutSection
            addItem:[OWSTableItem
                         disclosureItemWithText:
                             NSLocalizedString(@"SETTINGS_SCREEN_LOCK_ACTIVITY_TIMEOUT",
                                 @"Label for the 'screen lock activity timeout' setting of the privacy settings.")
                                     detailText:screenLockTimeoutString
                        accessibilityIdentifier:[NSString
                                                    stringWithFormat:@"settings.privacy.%@", @"screen_lock_timeout"]
                                    actionBlock:^{
                                        [weakSelf showScreenLockTimeoutUI];
                                    }]];
        [contents addSection:screenLockTimeoutSection];
    }

    OWSTableSection *screenSecuritySection = [OWSTableSection new];
    screenSecuritySection.headerTitle = NSLocalizedString(@"SETTINGS_SECURITY_TITLE", @"Section header");
    screenSecuritySection.footerTitle = NSLocalizedString(@"Prevent Session previews from appearing in the app switcher.", nil);
    [screenSecuritySection
        addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"Disable Preview in App Switcher", @"")
                    accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"screen_security"]
                    isOnBlock:^{
                        return [SMKPreferences isScreenSecurityEnabled];
                    }
                    isEnabledBlock:^{
                        return YES;
                    }
                    target:weakSelf
                    selector:@selector(didToggleScreenSecuritySwitch:)]];
    [contents addSection:screenSecuritySection];

    OWSTableSection *historyLogsSection = [OWSTableSection new];
    historyLogsSection.headerTitle = NSLocalizedString(@"SETTINGS_HISTORYLOG_TITLE", @"Section header");
    [historyLogsSection
        addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_CLEAR_HISTORY", @"")
                             accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"clear_logs"]
                                         actionBlock:^{
                                             [weakSelf clearHistoryLogs];
                                         }]];
    [contents addSection:historyLogsSection];

    OWSTableSection *linkPreviewsSection = [OWSTableSection new];
    [linkPreviewsSection
        addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"SETTINGS_LINK_PREVIEWS",
                                                     @"Setting for enabling & disabling link previews.")
                    accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"link_previews"]
                    isOnBlock:^{
                        return [SMKPreferences areLinkPreviewsEnabled];
                    }
                    isEnabledBlock:^{
                        return YES;
                    }
                    target:weakSelf
                    selector:@selector(didToggleLinkPreviewsEnabled:)]];
    linkPreviewsSection.headerTitle = NSLocalizedString(
        @"SETTINGS_LINK_PREVIEWS_HEADER", @"Header for setting for enabling & disabling link previews.");
    linkPreviewsSection.footerTitle = NSLocalizedString(
        @"SETTINGS_LINK_PREVIEWS_FOOTER", @"Footer for setting for enabling & disabling link previews.");
    [contents addSection:linkPreviewsSection];
    
    OWSTableSection *callsSection = [OWSTableSection new];
    [callsSection
        addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"SETTINGS_CALLS",
                                                     @"Setting for enabling & disabling voice & video calls.")
                    accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"calls"]
                    isOnBlock:^{
                        return [SMKPreferences areCallsEnabled];
                    }
                    isEnabledBlock:^{
                        return YES;
                    }
                    target:weakSelf
                    selector:@selector(didToggleCallsEnabled:)]];
    callsSection.headerTitle = [NSString stringWithFormat:@"%@ (BETA)", NSLocalizedString( @"SETTINGS_CALLS_HEADER", @"Header for setting for enabling & disabling voice & video calls.")];
    callsSection.footerTitle = NSLocalizedString(
        @"SETTINGS_CALLS_FOOTER", @"Footer for setting for enabling & disabling voice & video calls.");
    [contents addSection:callsSection];

    self.contents = contents;
}

#pragma mark - Events

- (void)clearHistoryLogs
{
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:nil
                                            message:NSLocalizedString(@"Are you sure? This cannot be undone.",
                                                        @"Alert message before user confirms clearing history")
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[OWSAlerts cancelAction]];

    UIAlertAction *deleteAction =
        [UIAlertAction actionWithTitle:
                           NSLocalizedString(@"SETTINGS_DELETE_HISTORYLOG_CONFIRMATION_BUTTON",
                               @"Confirmation text for button which deletes all message, calling, attachments, etc.")
               accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"delete")
                                 style:UIAlertActionStyleDestructive
                               handler:^(UIAlertAction *_Nonnull action) {
                                   [self deleteThreadsAndMessages];
                               }];
    [alert addAction:deleteAction];

    [self presentAlert:alert];
}

- (void)deleteThreadsAndMessages
{
    [SMKThread deleteAll];
}

- (void)didToggleScreenSecuritySwitch:(UISwitch *)sender
{
    BOOL enabled = sender.isOn;
    OWSLogInfo(@"toggled screen security: %@", enabled ? @"ON" : @"OFF");
    [SMKPreferences setScreenSecurity:enabled];
}

- (void)didToggleReadReceiptsSwitch:(UISwitch *)sender
{
    BOOL enabled = sender.isOn;
    OWSLogInfo(@"toggled areReadReceiptsEnabled: %@", enabled ? @"ON" : @"OFF");
    [SMKPreferences setAreReadReceiptsEnabled:enabled];
}

- (void)didToggleTypingIndicatorsSwitch:(UISwitch *)sender
{
    BOOL enabled = sender.isOn;
    OWSLogInfo(@"toggled areTypingIndicatorsEnabled: %@", enabled ? @"ON" : @"OFF");
    [SMKPreferences setTypingIndicatorsEnabled:enabled];
}

- (void)didToggleLinkPreviewsEnabled:(UISwitch *)sender
{
    BOOL enabled = sender.isOn;
    OWSLogInfo(@"toggled to: %@", (enabled ? @"ON" : @"OFF"));
    [SMKPreferences setLinkPreviewsEnabled:enabled];
}

- (void)didToggleCallsEnabled:(UISwitch *)sender
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    BOOL enabled = sender.isOn;
    if (enabled && ![userDefaults boolForKey:@"hasSeenCallIPExposureWarning"]) {
        [userDefaults setBool:YES forKey:@"hasSeenCallIPExposureWarning"];
        CallModal *modal = [[CallModal alloc] initOnCallEnabled:^{
            OWSLogInfo(@"toggled to: %@", (enabled ? @"ON" : @"OFF"));
            [self objc_requestMicrophonePermissionIfNeeded];
        }];
        [self presentViewController:modal animated:YES completion:nil];
    }
    else {
        OWSLogInfo(@"toggled to: %@", (enabled ? @"ON" : @"OFF"));
        [SMKPreferences setCallsEnabled:enabled];
    }
}

- (void)isScreenLockEnabledDidChange:(UISwitch *)sender
{
    BOOL shouldBeEnabled = sender.isOn;

    if (shouldBeEnabled == OWSScreenLock.sharedManager.isScreenLockEnabled) {
        OWSLogError(@"ignoring redundant screen lock.");
        return;
    }

    OWSLogInfo(@"trying to set is screen lock enabled: %@", @(shouldBeEnabled));
    
    [OWSScreenLock.sharedManager setIsScreenLockEnabled:shouldBeEnabled];
}

- (void)screenLockDidChange:(NSNotification *)notification
{
    OWSLogInfo(@"");

    [self updateTableContents];
}

- (void)showScreenLockTimeoutUI
{
    OWSLogInfo(@"");

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"SETTINGS_SCREEN_LOCK_ACTIVITY_TIMEOUT",
                                     @"Label for the 'screen lock activity timeout' setting of the privacy settings.")
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *timeoutValue in OWSScreenLock.sharedManager.screenLockTimeouts) {
        uint32_t screenLockTimeout = (uint32_t)round(timeoutValue.doubleValue);
        NSString *screenLockTimeoutString = [self formatScreenLockTimeout:screenLockTimeout useShortFormat:NO];

        UIAlertAction *action =
            [UIAlertAction actionWithTitle:screenLockTimeoutString
                   accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.timeout.%@", timeoutValue]
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *ignore) {
                                       [OWSScreenLock.sharedManager setScreenLockTimeout:screenLockTimeout];
                                   }];
        [alert addAction:action];
    }
    [alert addAction:[OWSAlerts cancelAction]];
    UIViewController *fromViewController = [[UIApplication sharedApplication] frontmostViewController];
    [fromViewController presentAlert:alert];
}

- (NSString *)formatScreenLockTimeout:(NSInteger)value useShortFormat:(BOOL)useShortFormat
{
    if (value <= 1) {
        return NSLocalizedString(@"SCREEN_LOCK_ACTIVITY_TIMEOUT_NONE",
            @"Indicates a delay of zero seconds, and that 'screen lock activity' will timeout immediately.");
    }
    return [NSString formatDurationSeconds:(uint32_t)value useShortFormat:useShortFormat];
}

- (void)close: (UIBarButtonItem *)sender
{
    [[self navigationController] dismissViewControllerAnimated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
