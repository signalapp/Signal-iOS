//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "AdvancedSettingsTableViewController.h"
#import "DebugLogger.h"
#import "DomainFrontingCountryViewController.h"
#import "OWSCountryMetadata.h"
#import "Pastelog.h"
#import "RegistrationUtils.h"
#import "Signal-Swift.h"
#import "TSAccountManager.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation AdvancedSettingsTableViewController

- (void)loadView
{
    [super loadView];

    self.title = NSLocalizedString(@"SETTINGS_ADVANCED_TITLE", @"");

    self.useThemeBackgroundColors = YES;

    [self observeNotifications];

    [self updateTableContents];
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(socketStateDidChange)
                                                 name:NSNotificationWebSocketStateDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityChanged)
                                                 name:SSKReachability.owsReachabilityDidChange
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)socketStateDidChange
{
    OWSAssertIsOnMainThread();

    [self updateTableContents];
}

- (void)reachabilityChanged
{
    OWSAssertIsOnMainThread();

    [self updateTableContents];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self updateTableContents];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak AdvancedSettingsTableViewController *weakSelf = self;

    OWSTableSection *loggingSection = [OWSTableSection new];
    loggingSection.headerTitle = NSLocalizedString(@"LOGGING_SECTION", nil);
    [loggingSection addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"SETTINGS_ADVANCED_DEBUGLOG", @"")
                                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"enable_debug_log")
                                isOnBlock:^{
                                    return [OWSPreferences isLoggingEnabled];
                                }
                                isEnabledBlock:^{
                                    return YES;
                                }
                                target:weakSelf
                                selector:@selector(didToggleEnableLogSwitch:)]];

    if ([OWSPreferences isLoggingEnabled]) {
        [loggingSection
            addItem:[OWSTableItem actionItemWithText:NSLocalizedString(@"SETTINGS_ADVANCED_SUBMIT_DEBUGLOG", @"")
                             accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"submit_debug_log")
                                         actionBlock:^{
                                             OWSLogInfo(@"Submitting debug logs");
                                             [DDLog flushLog];
                                             [Pastelog submitLogs];
                                         }]];
    }

    if (SSKDebugFlags.audibleErrorLogging) {
        [loggingSection
            addItem:[OWSTableItem actionItemWithText:NSLocalizedString(
                                                         @"SETTINGS_ADVANCED_VIEW_ERROR_LOG", @"table cell label")
                             accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"view_error_log")
                                         actionBlock:^{
                                             [weakSelf didPressViewErrorLog];
                                         }]];
    }

    [contents addSection:loggingSection];

    OWSTableSection *pushNotificationsSection = [OWSTableSection new];
    pushNotificationsSection.headerTitle
        = NSLocalizedString(@"PUSH_REGISTER_TITLE", @"Used in table section header and alert view title contexts");
    [pushNotificationsSection addItem:[OWSTableItem actionItemWithText:NSLocalizedString(@"REREGISTER_FOR_PUSH", nil)
                                               accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                                           self, @"reregister_push_notifications")
                                                           actionBlock:^{
                                                               [weakSelf syncPushTokens];
                                                           }]];
    [contents addSection:pushNotificationsSection];

    // Censorship circumvention has certain disadvantages so it should only be
    // used if necessary.  Therefore:
    //
    // * We disable this setting if the user has a phone number from a censored region -
    //   censorship circumvention will be auto-activated for this user.
    // * We disable this setting if the user is already connected; they're not being
    //   censored.
    // * We continue to show this setting so long as it is set to allow users to disable
    //   it, for example when they leave a censored region.
    OWSTableSection *censorshipSection = [OWSTableSection new];
    censorshipSection.headerTitle = NSLocalizedString(@"SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_HEADER",
        @"Table header for the 'censorship circumvention' section.");
    BOOL isAnySocketOpen = TSSocketManager.shared.socketState == OWSWebSocketStateOpen;
    if (OWSSignalService.shared.hasCensoredPhoneNumber) {
        if (OWSSignalService.shared.isCensorshipCircumventionManuallyDisabled) {
            censorshipSection.footerTitle
                = NSLocalizedString(@"SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER_MANUALLY_DISABLED",
                    @"Table footer for the 'censorship circumvention' section shown when censorship circumvention has "
                    @"been manually disabled.");
        } else {
            censorshipSection.footerTitle = NSLocalizedString(
                @"SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER_AUTO_ENABLED",
                @"Table footer for the 'censorship circumvention' section shown when censorship circumvention has been "
                @"auto-enabled based on local phone number.");
        }
    } else if (isAnySocketOpen) {
        censorshipSection.footerTitle
            = NSLocalizedString(@"SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER_WEBSOCKET_CONNECTED",
                @"Table footer for the 'censorship circumvention' section shown when the app is connected to the "
                @"Signal service.");
    } else if (!self.reachabilityManager.isReachable) {
        censorshipSection.footerTitle
            = NSLocalizedString(@"SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER_NO_CONNECTION",
                @"Table footer for the 'censorship circumvention' section shown when the app is not connected to the "
                @"internet.");
    } else {
        censorshipSection.footerTitle = NSLocalizedString(@"SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER",
            @"Table footer for the 'censorship circumvention' section when censorship circumvention can be manually "
            @"enabled.");
    }

    // Do enable if :
    //
    // * ...Censorship circumvention is already manually enabled (to allow users to disable it).
    //
    // Otherwise, don't enable if:
    //
    // * ...Censorship circumvention is already enabled based on the local phone number.
    // * ...The websocket is connected, since that demonstrates that no censorship is in effect.
    // * ...The internet is not reachable, since we don't want to let users to activate
    //      censorship circumvention unnecessarily, e.g. if they just don't have a valid
    //      internet connection.
    OWSTableSwitchBlock isCensorshipCircumventionOnBlock
        = ^{ return OWSSignalService.shared.isCensorshipCircumventionActive; };
    // Close over reachabilityManager to avoid leaking a reference to self.
    id<SSKReachabilityManager> reachabilityManager = self.reachabilityManager;
    OWSTableSwitchBlock isManualCensorshipCircumventionOnEnabledBlock = ^{
        OWSSignalService *service = OWSSignalService.shared;
        if (SSKDebugFlags.exposeCensorshipCircumvention) {
            return YES;
        } else if (service.isCensorshipCircumventionActive) {
            return YES;
        } else if (service.hasCensoredPhoneNumber && service.isCensorshipCircumventionManuallyDisabled) {
            return YES;
        } else if (TSSocketManager.shared.socketState == OWSWebSocketStateOpen) {
            return NO;
        } else {
            return reachabilityManager.isReachable;
        }
    };

    [censorshipSection
        addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION",
                                                     @"Label for the  'manual censorship circumvention' switch.")
                         accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"censorship_circumvention")
                                       isOnBlock:isCensorshipCircumventionOnBlock
                                  isEnabledBlock:isManualCensorshipCircumventionOnEnabledBlock
                                          target:weakSelf
                                        selector:@selector(didToggleEnableCensorshipCircumventionSwitch:)]];

    if (OWSSignalService.shared.isCensorshipCircumventionManuallyActivated) {
        OWSCountryMetadata *manualCensorshipCircumventionCountry =
            [weakSelf ensureManualCensorshipCircumventionCountry];
        OWSAssertDebug(manualCensorshipCircumventionCountry);
        NSString *text = [NSString
            stringWithFormat:NSLocalizedString(@"SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_COUNTRY_FORMAT",
                                 @"Label for the 'manual censorship circumvention' country. Embeds {{the manual "
                                 @"censorship circumvention country}}."),
            manualCensorshipCircumventionCountry.localizedCountryName];
        [censorshipSection addItem:[OWSTableItem disclosureItemWithText:text
                                                            actionBlock:^{
                                                                [weakSelf showDomainFrontingCountryView];
                                                            }]];
    }
    [contents addSection:censorshipSection];

    OWSTableSection *pinsSection = [OWSTableSection new];
    pinsSection.headerTitle
        = NSLocalizedString(@"SETTINGS_ADVANCED_PINS_HEADER", @"Table header for the 'pins' section.");
    [pinsSection addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_ADVANCED_PIN_SETTINGS",
                                                                  @"Label for the 'advanced pin settings' button.")
                                      accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"pins")
                                                  actionBlock:^{
                                                      [weakSelf showAdvancedPinSettings];
                                                  }]];
    [contents addSection:pinsSection];

    OWSTableSection *deleteAccountSection = [OWSTableSection new];
    deleteAccountSection.customHeaderView = [UIView spacerWithHeight:24];

    if (self.tsAccountManager.isDeregistered) {
        [deleteAccountSection
            addItem:[self destructiveButtonItemWithTitle:self.tsAccountManager.isPrimaryDevice
                              ? NSLocalizedString(@"SETTINGS_REREGISTER_BUTTON", @"Label for re-registration button.")
                              : NSLocalizedString(@"SETTINGS_RELINK_BUTTON", @"Label for re-link button.")
                                 accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"reregister")
                                                selector:@selector(reregisterUser)
                                                   color:Theme.accentBlueColor]];
        [deleteAccountSection
            addItem:[self destructiveButtonItemWithTitle:NSLocalizedString(@"SETTINGS_DELETE_DATA_BUTTON",
                                                             @"Label for 'delete data' button.")
                                 accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"delete_data")
                                                selector:@selector(deleteUnregisterUserData)
                                                   color:UIColor.ows_accentRedColor]];
    } else if (self.tsAccountManager.isRegisteredPrimaryDevice) {
        [deleteAccountSection
            addItem:[self destructiveButtonItemWithTitle:NSLocalizedString(@"SETTINGS_DELETE_ACCOUNT_BUTTON", @"")
                                 accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"delete_account")
                                                selector:@selector(unregisterUser)
                                                   color:UIColor.ows_accentRedColor]];
    } else {
        [deleteAccountSection
            addItem:[self destructiveButtonItemWithTitle:NSLocalizedString(@"SETTINGS_DELETE_DATA_BUTTON",
                                                             @"Label for 'delete data' button.")
                                 accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"delete_data")
                                                selector:@selector(deleteLinkedData)
                                                   color:UIColor.ows_accentRedColor]];
    }

    [contents addSection:deleteAccountSection];

    self.contents = contents;
}

- (void)showDomainFrontingCountryView
{
    DomainFrontingCountryViewController *vc = [DomainFrontingCountryViewController new];
    [self.navigationController pushViewController:vc animated:YES];
}

- (OWSCountryMetadata *)ensureManualCensorshipCircumventionCountry
{
    OWSAssertIsOnMainThread();

    OWSCountryMetadata *countryMetadata = nil;
    NSString *countryCode = OWSSignalService.shared.manualCensorshipCircumventionCountryCode;
    if (countryCode) {
        countryMetadata = [OWSCountryMetadata countryMetadataForCountryCode:countryCode];
    }

    if (!countryMetadata) {
        countryCode = [PhoneNumber defaultCountryCode];
        if (countryCode) {
            countryMetadata = [OWSCountryMetadata countryMetadataForCountryCode:countryCode];
        }
    }

    if (!countryMetadata) {
        countryCode = @"US";
        countryMetadata = [OWSCountryMetadata countryMetadataForCountryCode:countryCode];
        OWSAssertDebug(countryMetadata);
    }

    if (countryMetadata) {
        // Ensure the "manual censorship circumvention" country state is in sync.
        OWSSignalService.shared.manualCensorshipCircumventionCountryCode = countryCode;
    }

    return countryMetadata;
}

#pragma mark - Actions

- (void)showAdvancedPinSettings
{
    AdvancedPinSettingsTableViewController *vc = [AdvancedPinSettingsTableViewController new];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)syncPushTokens
{
    OWSSyncPushTokensJob *job =
        [[OWSSyncPushTokensJob alloc] initWithAccountManager:AppEnvironment.shared.accountManager
                                                 preferences:Environment.shared.preferences];
    job.uploadOnlyIfStale = NO;
    [job run]
        .then(^{
            [OWSActionSheets showActionSheetWithTitle:NSLocalizedString(@"PUSH_REGISTER_SUCCESS",
                                                          @"Title of alert shown when push tokens sync job succeeds.")];
        })
        .catch(^(NSError *error) {
            [OWSActionSheets showActionSheetWithTitle:NSLocalizedString(@"REGISTRATION_BODY",
                                                          @"Title of alert shown when push tokens sync job fails.")];
        });
}

- (void)didToggleEnableLogSwitch:(UISwitch *)sender
{
    if (!sender.isOn) {
        OWSLogInfo(@"disabling logging.");
        [[DebugLogger sharedLogger] wipeLogs];
        [[DebugLogger sharedLogger] disableFileLogging];
    } else {
        [[DebugLogger sharedLogger] enableFileLogging];
        OWSLogInfo(@"enabling logging.");
    }

    [OWSPreferences setIsLoggingEnabled:sender.isOn];

    [self updateTableContents];
}

- (void)didToggleEnableCensorshipCircumventionSwitch:(UISwitch *)sender
{
    OWSSignalService *service = OWSSignalService.shared;
    if (sender.isOn) {
        service.isCensorshipCircumventionManuallyDisabled = NO;
        service.isCensorshipCircumventionManuallyActivated = YES;
    } else {
        service.isCensorshipCircumventionManuallyDisabled = YES;
        service.isCensorshipCircumventionManuallyActivated = NO;
    }

    [self updateTableContents];
}

- (void)didPressViewErrorLog
{
    OWSAssertDebug(SSKDebugFlags.audibleErrorLogging);

    [DDLog flushLog];
    NSURL *errorLogsDir = DebugLogger.sharedLogger.errorLogsDir;
    LogPickerViewController *logPicker = [[LogPickerViewController alloc] initWithLogDirUrl:errorLogsDir];
    [self.navigationController pushViewController:logPicker animated:YES];
}

#pragma mark - Unregister & Re-register

- (void)unregisterUser
{
    [self showDeleteAccountUI:YES];
}

- (void)deleteLinkedData
{
    ActionSheetController *actionSheet =
        [[ActionSheetController alloc] initWithTitle:NSLocalizedString(@"CONFIRM_DELETE_LINKED_DATA_TITLE", @"")
                                             message:NSLocalizedString(@"CONFIRM_DELETE_LINKED_DATA_TEXT", @"")];
    [actionSheet addAction:[[ActionSheetAction alloc] initWithTitle:NSLocalizedString(@"PROCEED_BUTTON", @"")
                                                              style:ActionSheetActionStyleDestructive
                                                            handler:^(ActionSheetAction *action) {
                                                                [SignalApp resetAppData];
                                                            }]];
    [actionSheet addAction:[OWSActionSheets cancelAction]];

    [self presentActionSheet:actionSheet];
}

- (void)reregisterUser
{
    [RegistrationUtils showReregistrationUIFromViewController:self];
}

- (void)deleteUnregisterUserData
{
    [self showDeleteAccountUI:NO];
}

- (void)showDeleteAccountUI:(BOOL)isRegistered
{
    __weak AdvancedSettingsTableViewController *weakSelf = self;

    ActionSheetController *actionSheet =
        [[ActionSheetController alloc] initWithTitle:NSLocalizedString(@"CONFIRM_ACCOUNT_DESTRUCTION_TITLE", @"")
                                             message:NSLocalizedString(@"CONFIRM_ACCOUNT_DESTRUCTION_TEXT", @"")];
    [actionSheet addAction:[[ActionSheetAction alloc] initWithTitle:NSLocalizedString(@"PROCEED_BUTTON", @"")
                                                              style:ActionSheetActionStyleDestructive
                                                            handler:^(ActionSheetAction *action) {
                                                                [weakSelf deleteAccount:isRegistered];
                                                            }]];
    [actionSheet addAction:[OWSActionSheets cancelAction]];

    [self presentActionSheet:actionSheet];
}

- (void)deleteAccount:(BOOL)isRegistered
{
    if (isRegistered) {
        [ModalActivityIndicatorViewController
            presentFromViewController:self
                            canCancel:NO
                      backgroundBlock:^(ModalActivityIndicatorViewController *modalActivityIndicator) {
                          [TSAccountManager
                              unregisterTextSecureWithSuccess:^{
                                  [SignalApp resetAppData];
                              }
                              failure:^(NSError *error) {
                                  dispatch_async(dispatch_get_main_queue(), ^{
                                      [modalActivityIndicator dismissWithCompletion:^{
                                          [OWSActionSheets
                                              showActionSheetWithTitle:NSLocalizedString(
                                                                           @"UNREGISTER_SIGNAL_FAIL", @"")];
                                      }];
                                  });
                              }];
                      }];
    } else {
        [SignalApp resetAppData];
    }
}

- (OWSTableItem *)destructiveButtonItemWithTitle:(NSString *)title
                         accessibilityIdentifier:(NSString *)accessibilityIdentifier
                                        selector:(SEL)selector
                                           color:(UIColor *)color
{
    __weak AdvancedSettingsTableViewController *weakSelf = self;
    OWSTableItem *item = [OWSTableItem
        itemWithCustomCellBlock:^{
            UITableViewCell *cell = [OWSTableItem newCell];
            cell.preservesSuperviewLayoutMargins = YES;
            cell.contentView.preservesSuperviewLayoutMargins = YES;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.contentView.backgroundColor = Theme.tableViewBackgroundColor;

            const CGFloat kButtonHeight = 40.f;
            OWSFlatButton *button = [OWSFlatButton buttonWithTitle:title
                                                              font:[OWSFlatButton fontForHeight:kButtonHeight]
                                                        titleColor:[UIColor whiteColor]
                                                   backgroundColor:color
                                                            target:weakSelf
                                                          selector:selector];
            [cell.contentView addSubview:button];
            [button autoSetDimension:ALDimensionHeight toSize:kButtonHeight];
            [button autoVCenterInSuperview];
            [button autoPinLeadingAndTrailingToSuperviewMargin];
            button.accessibilityIdentifier = accessibilityIdentifier;

            return cell;
        }
                    actionBlock:nil];
    item.customRowHeight = @(90.f);
    return item;
}

@end

NS_ASSUME_NONNULL_END
