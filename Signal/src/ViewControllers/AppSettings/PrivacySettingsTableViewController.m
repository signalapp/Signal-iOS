//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "PrivacySettingsTableViewController.h"
#import "BlockListViewController.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/ThreadUtil.h>
#import <SignalServiceKit/OWS2FAManager.h>
#import <SignalServiceKit/OWSReadReceiptManager.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@import SafariServices;
@import PromiseKit;

NS_ASSUME_NONNULL_BEGIN

@implementation PrivacySettingsTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = NSLocalizedString(@"SETTINGS_PRIVACY_TITLE", @"");

    self.useThemeBackgroundColors = YES;

    [self observeNotifications];

    [self updateTableContents];
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

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(configurationSettingsDidChange:) name:OWSSyncManagerConfigurationSyncDidCompleteNotification object:nil];
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

    OWSTableSection *whoCanSection = [OWSTableSection new];
    whoCanSection.headerTitle = NSLocalizedString(@"SETTINGS_WHO_CAN", @"Label for the 'who can' privacy settings.");

    if (SSKFeatureFlags.phoneNumberSharing) {
        [whoCanSection
            addItem:[OWSTableItem
                         disclosureItemWithText:NSLocalizedString(@"SETTINGS_PHONE_NUMBER_SHARING",
                                                    @"Label for the 'phone number sharing' setting.")
                                     detailText:PhoneNumberSharingSettingsTableViewController.nameForCurrentMode
                        accessibilityIdentifier:[NSString
                                                    stringWithFormat:@"settings.privacy.%@", @"phone_number_sharing"]
                                    actionBlock:^{
                                        PhoneNumberSharingSettingsTableViewController *vc =
                                            [PhoneNumberSharingSettingsTableViewController new];
                                        [weakSelf.navigationController pushViewController:vc animated:YES];
                                    }]];
    }

    if (SSKFeatureFlags.phoneNumberDiscoverability) {
        [whoCanSection
            addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_PHONE_NUMBER_DISCOVERABILITY",
                                                             @"Label for the 'phone number discoverability' setting.")
                                              detailText:PhoneNumberDiscoverabilitySettingsTableViewController
                                                             .nameForCurrentDiscoverability
                                 accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@",
                                                                   @"phone_number_discoverability"]
                                             actionBlock:^{
                                                 PhoneNumberDiscoverabilitySettingsTableViewController *vc =
                                                     [PhoneNumberDiscoverabilitySettingsTableViewController new];
                                                 [weakSelf.navigationController pushViewController:vc animated:YES];
                                             }]];
    }

    if (whoCanSection.itemCount > 0) {
        [contents addSection:whoCanSection];
    }

    OWSTableSection *readReceiptsSection = [OWSTableSection new];
    readReceiptsSection.headerTitle
        = NSLocalizedString(@"SETTINGS_MESSAGING", @"Label for the 'messaging' privacy settings.");
    readReceiptsSection.footerTitle = NSLocalizedString(
        @"SETTINGS_READ_RECEIPTS_SECTION_FOOTER", @"An explanation of the 'read receipts' setting.");
    [readReceiptsSection
        addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"SETTINGS_READ_RECEIPT",
                                                     @"Label for the 'read receipts' setting.")
                    accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"read_receipts"]
                    isOnBlock:^{ return [OWSReadReceiptManager.shared areReadReceiptsEnabled]; }
                    isEnabledBlock:^{ return YES; }
                    target:weakSelf
                    selector:@selector(didToggleReadReceiptsSwitch:)]];
    [contents addSection:readReceiptsSection];

    OWSTableSection *typingIndicatorsSection = [OWSTableSection new];
    typingIndicatorsSection.footerTitle = NSLocalizedString(
        @"SETTINGS_TYPING_INDICATORS_FOOTER", @"An explanation of the 'typing indicators' setting.");
    [typingIndicatorsSection
        addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"SETTINGS_TYPING_INDICATORS",
                                                     @"Label for the 'typing indicators' setting.")
                    accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"typing_indicators"]
                    isOnBlock:^{
                        return [SSKEnvironment.shared.typingIndicators areTypingIndicatorsEnabled];
                    }
                    isEnabledBlock:^{
                        return YES;
                    }
                    target:weakSelf
                    selector:@selector(didToggleTypingIndicatorsSwitch:)]];
    [contents addSection:typingIndicatorsSection];

    OWSTableSection *linkPreviewsSection = [OWSTableSection new];
    [linkPreviewsSection
        addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"SETTINGS_LINK_PREVIEWS",
                                                     @"Setting for enabling & disabling link previews.")
                    accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"link_previews"]
                    isOnBlock:^{
                        if (!weakSelf) {
                            return NO;
                        }
                        PrivacySettingsTableViewController *strongSelf = weakSelf;

                        __block BOOL areLinkPreviewsEnabled;
                        [strongSelf.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
                            areLinkPreviewsEnabled = [SSKPreferences areLinkPreviewsEnabledWithTransaction:transaction];
                        }];
                        return areLinkPreviewsEnabled;
                    }
                    isEnabledBlock:^{
                        return YES;
                    }
                    target:weakSelf
                    selector:@selector(didToggleLinkPreviewsEnabled:)]];
    linkPreviewsSection.footerTitle = NSLocalizedString(
        @"SETTINGS_LINK_PREVIEWS_FOOTER", @"Footer for setting for enabling & disabling link previews.");
    [contents addSection:linkPreviewsSection];

    OWSTableSection *blocklistSection = [OWSTableSection new];
    blocklistSection.footerTitle
        = NSLocalizedString(@"SETTINGS_BLOCK_LIST_FOOTER", @"An explanation of the 'blocked' setting");
    [blocklistSection
        addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_BLOCK_LIST_TITLE",
                                                         @"Label for the block list section of the settings view")
                             accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"blocklist"]
                                         actionBlock:^{
                                             [weakSelf showBlocklist];
                                         }]];
    [contents addSection:blocklistSection];

    // Allow calls to connect directly vs. using TURN exclusively
    OWSTableSection *callingSection = [OWSTableSection new];
    callingSection.headerTitle
        = NSLocalizedString(@"SETTINGS_SECTION_TITLE_CALLING", @"settings topic header for table section");
    callingSection.footerTitle = NSLocalizedString(@"SETTINGS_CALLING_HIDES_IP_ADDRESS_PREFERENCE_TITLE_DETAIL",
        @"User settings section footer, a detailed explanation");
    [callingSection addItem:[OWSTableItem switchItemWithText:NSLocalizedString(
                                                                 @"SETTINGS_CALLING_HIDES_IP_ADDRESS_PREFERENCE_TITLE",
                                                                 @"Table cell label")
                                accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@",
                                                                  @"calling_hide_ip_address"]
                                isOnBlock:^{
                                    return [Environment.shared.preferences doCallsHideIPAddress];
                                }
                                isEnabledBlock:^{
                                    return YES;
                                }
                                target:weakSelf
                                selector:@selector(didToggleCallsHideIPAddressSwitch:)]];
    [contents addSection:callingSection];

    if (CallUIAdapter.isCallkitDisabledForLocale) {
        // Hide all CallKit-related prefs; CallKit is disabled.
    } else {
        OWSTableSection *callKitSection = [OWSTableSection new];
        [callKitSection
            addItem:[OWSTableItem switchItemWithText:NSLocalizedString(
                                                         @"SETTINGS_PRIVACY_CALLKIT_SYSTEM_CALL_LOG_PREFERENCE_TITLE",
                                                         @"Short table cell label")
                        accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"callkit_history"]
                        isOnBlock:^{
                            return [Environment.shared.preferences isSystemCallLogEnabled];
                        }
                        isEnabledBlock:^{
                            return YES;
                        }
                        target:weakSelf
                        selector:@selector(didToggleEnableSystemCallLogSwitch:)]];
        callKitSection.footerTitle = NSLocalizedString(
            @"SETTINGS_PRIVACY_CALLKIT_SYSTEM_CALL_LOG_PREFERENCE_DESCRIPTION", @"Settings table section footer.");
        [contents addSection:callKitSection];
    }

    // Show the change pin and reglock sections
    if (self.tsAccountManager.isRegisteredPrimaryDevice) {
        OWSTableSection *pinsSection = [OWSTableSection new];
        pinsSection.headerTitle
            = NSLocalizedString(@"SETTINGS_PINS_TITLE", @"Title for the 'PINs' section of the privacy settings.");

        NSMutableAttributedString *attributedFooter = [[NSMutableAttributedString alloc]
            initWithString:NSLocalizedString(
                               @"SETTINGS_PINS_FOOTER", @"Footer for the 'PINs' section of the privacy settings.")
                attributes:@{
                    NSForegroundColorAttributeName : UIColor.ows_gray45Color,
                    NSFontAttributeName : UIFont.ows_dynamicTypeCaption1Font
                }];
        [attributedFooter appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:@{}]];
        [attributedFooter appendAttributedString:
                              [[NSAttributedString alloc]
                                  initWithString:CommonStrings.learnMore
                                      attributes:@{
                                          NSLinkAttributeName : [NSURL
                                              URLWithString:@"https://support.signal.org/hc/articles/360007059792"],
                                          NSFontAttributeName : UIFont.ows_dynamicTypeCaption1Font
                                      }]];
        pinsSection.footerAttributedTitle = attributedFooter;

        [pinsSection
            addItem:[OWSTableItem disclosureItemWithText:([OWS2FAManager.shared is2FAEnabled]
                                                                 ? NSLocalizedString(@"SETTINGS_PINS_ITEM",
                                                                     @"Label for the 'pins' item of the privacy "
                                                                     @"settings when the user does have a pin.")
                                                                 : NSLocalizedString(@"SETTINGS_PINS_ITEM_CREATE",
                                                                     @"Label for the 'pins' item of the privacy "
                                                                     @"settings when the user doesn't have a pin."))
                                 accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"pin"]
                                             actionBlock:^{
                                                 if ([OWS2FAManager.shared is2FAEnabled]) {
                                                     [weakSelf showChangePin];
                                                 } else {
                                                     [weakSelf showCreatePin];
                                                 }
                                             }]];
        [contents addSection:pinsSection];

        if ([OWS2FAManager.shared is2FAEnabled]) {
            OWSTableSection *reminderSection = [OWSTableSection new];
            reminderSection.footerTitle = NSLocalizedString(@"SETTINGS_PIN_REMINDER_FOOTER",
                @"Footer for the 'pin reminder' section of the privacy settings when Signal PINs are available.");
            [reminderSection
                addItem:[OWSTableItem
                            switchItemWithText:NSLocalizedString(@"SETTINGS_PIN_REMINDER_SWITCH_LABEL",
                                                   @"Label for the 'pin reminder' switch of the privacy settings.")
                            accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"2fa"]
                            isOnBlock:^{ return OWS2FAManager.shared.areRemindersEnabled; }
                            isEnabledBlock:^{ return YES; }
                            target:self
                            selector:@selector(arePINRemindersEnabledDidChange:)]];
            [contents addSection:reminderSection];
        }

        OWSTableSection *registrationLockSection = [OWSTableSection new];
        registrationLockSection.footerTitle = NSLocalizedString(@"SETTINGS_TWO_FACTOR_PINS_AUTH_FOOTER",
            @"Footer for the 'two factor auth' section of the privacy settings when Signal PINs are available.");
        [registrationLockSection
            addItem:[OWSTableItem switchItemWithText:
                                      NSLocalizedString(@"SETTINGS_TWO_FACTOR_AUTH_SWITCH_LABEL",
                                          @"Label for the 'enable registration lock' switch of the privacy settings.")
                        accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"2fa"]
                        isOnBlock:^{ return [OWS2FAManager.shared isRegistrationLockV2Enabled]; }
                        isEnabledBlock:^{ return YES; }
                        target:self
                        selector:@selector(isRegistrationLockV2EnabledDidChange:)]];
        [contents addSection:registrationLockSection];
    }

    OWSTableSection *screenLockSection = [OWSTableSection new];
    screenLockSection.headerTitle = NSLocalizedString(
        @"SETTINGS_SCREEN_LOCK_SECTION_TITLE", @"Title for the 'screen lock' section of the privacy settings.");
    screenLockSection.footerTitle = NSLocalizedString(
        @"SETTINGS_SCREEN_LOCK_SECTION_FOOTER", @"Footer for the 'screen lock' section of the privacy settings.");
    [screenLockSection
        addItem:[OWSTableItem
                    switchItemWithText:NSLocalizedString(@"SETTINGS_SCREEN_LOCK_SWITCH_LABEL",
                                           @"Label for the 'enable screen lock' switch of the privacy settings.")
                    accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"screenlock"]
                    isOnBlock:^{ return [OWSScreenLock.shared isScreenLockEnabled]; }
                    isEnabledBlock:^{ return YES; }
                    target:self
                    selector:@selector(isScreenLockEnabledDidChange:)]];
    [contents addSection:screenLockSection];

    if (OWSScreenLock.shared.isScreenLockEnabled) {
        OWSTableSection *screenLockTimeoutSection = [OWSTableSection new];
        uint32_t screenLockTimeout = (uint32_t)round(OWSScreenLock.shared.screenLockTimeout);
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
    screenSecuritySection.footerTitle = NSLocalizedString(@"SETTINGS_SCREEN_SECURITY_DETAIL", nil);
    [screenSecuritySection
        addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"SETTINGS_SCREEN_SECURITY", @"")
                    accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"screen_security"]
                    isOnBlock:^{
                        return [Environment.shared.preferences screenSecurityIsEnabled];
                    }
                    isEnabledBlock:^{
                        return YES;
                    }
                    target:weakSelf
                    selector:@selector(didToggleScreenSecuritySwitch:)]];
    [contents addSection:screenSecuritySection];

    OWSTableSection *unidentifiedDeliveryIndicatorsSection = [OWSTableSection new];
    unidentifiedDeliveryIndicatorsSection.headerTitle
        = NSLocalizedString(@"SETTINGS_UNIDENTIFIED_DELIVERY_SECTION_TITLE", @"table section label");
    [unidentifiedDeliveryIndicatorsSection
        addItem:[OWSTableItem
                    itemWithCustomCellBlock:^UITableViewCell * {
                        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                                                       reuseIdentifier:@"UITableViewCellStyleValue1"];
                        [OWSTableItem configureCell:cell];
                        cell.preservesSuperviewLayoutMargins = YES;
                        cell.contentView.preservesSuperviewLayoutMargins = YES;
                        cell.selectionStyle = UITableViewCellSelectionStyleNone;

                        UILabel *label = [UILabel new];
                        label.text
                            = NSLocalizedString(@"SETTINGS_UNIDENTIFIED_DELIVERY_SHOW_INDICATORS", @"switch label");
                        label.font = OWSTableItem.primaryLabelFont;
                        label.textColor = Theme.primaryTextColor;
                        [label setContentHuggingHorizontalHigh];

                        UIImage *icon = [UIImage imageNamed:@"ic_secret_sender_indicator"];
                        UIImageView *iconView = [[UIImageView alloc]
                            initWithImage:[icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                        iconView.tintColor = Theme.secondaryTextAndIconColor;
                        [iconView setContentHuggingHorizontalHigh];

                        UIView *spacer = [UIView new];
                        [spacer setContentHuggingHorizontalLow];

                        UIStackView *stackView =
                            [[UIStackView alloc] initWithArrangedSubviews:@[ label, iconView, spacer ]];
                        stackView.axis = UILayoutConstraintAxisHorizontal;
                        stackView.spacing = 10;
                        stackView.alignment = UIStackViewAlignmentCenter;

                        [cell.contentView addSubview:stackView];
                        [stackView autoPinEdgesToSuperviewMargins];

                        UISwitch *cellSwitch = [UISwitch new];
                        [cellSwitch setOn:Environment.shared.preferences.shouldShowUnidentifiedDeliveryIndicators];
                        [cellSwitch addTarget:weakSelf
                                       action:@selector(didToggleUDShowIndicatorsSwitch:)
                             forControlEvents:UIControlEventValueChanged];
                        cell.accessoryView = cellSwitch;
                        cellSwitch.accessibilityIdentifier =
                            [NSString stringWithFormat:@"settings.privacy.%@", @"sealed_sender"];

                        return cell;
                    }
                                actionBlock:nil]];

    NSMutableAttributedString *unidentifiedDeliveryFooterText = [[NSMutableAttributedString alloc]
        initWithString:NSLocalizedString(
                           @"SETTINGS_UNIDENTIFIED_DELIVERY_SHOW_INDICATORS_FOOTER", @"table section footer")
            attributes:@{
                NSForegroundColorAttributeName : UIColor.ows_gray45Color,
                NSFontAttributeName : UIFont.ows_dynamicTypeCaption1Font
            }];
    [unidentifiedDeliveryFooterText appendAttributedString:[[NSAttributedString alloc] initWithString:@" "
                                                                                           attributes:@{}]];
    [unidentifiedDeliveryFooterText
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:CommonStrings.learnMore
                                       attributes:@{
                                           NSLinkAttributeName :
                                               [NSURL URLWithString:@"https://signal.org/blog/sealed-sender/"],
                                           NSFontAttributeName : UIFont.ows_dynamicTypeCaption1Font
                                       }]];

    unidentifiedDeliveryIndicatorsSection.footerAttributedTitle = unidentifiedDeliveryFooterText;
    [contents addSection:unidentifiedDeliveryIndicatorsSection];

    // Only the primary device can adjust the unrestricted UD setting. We don't sync this setting.
    if (self.tsAccountManager.isRegisteredPrimaryDevice) {
        OWSTableSection *unidentifiedDeliveryUnrestrictedSection = [OWSTableSection new];
        OWSTableItem *unrestrictedAccessItem = [OWSTableItem
            switchItemWithText:NSLocalizedString(@"SETTINGS_UNIDENTIFIED_DELIVERY_UNRESTRICTED_ACCESS", @"switch label")
            accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"sealed_sender_unrestricted"]
            isOnBlock:^{
                return [SSKEnvironment.shared.udManager shouldAllowUnrestrictedAccessLocal];
            }
            isEnabledBlock:^{
                return YES;
            }
            target:weakSelf
            selector:@selector(didToggleUDUnrestrictedAccessSwitch:)];
        [unidentifiedDeliveryUnrestrictedSection addItem:unrestrictedAccessItem];
        unidentifiedDeliveryUnrestrictedSection.footerTitle
            = NSLocalizedString(@"SETTINGS_UNIDENTIFIED_DELIVERY_UNRESTRICTED_ACCESS_FOOTER", @"table section footer");
        [contents addSection:unidentifiedDeliveryUnrestrictedSection];
    }

    OWSTableSection *historyLogsSection = [OWSTableSection new];
    historyLogsSection.headerTitle = NSLocalizedString(@"SETTINGS_HISTORYLOG_TITLE", @"Section header");
    [historyLogsSection
        addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_CLEAR_HISTORY", @"")
                             accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"clear_logs"]
                                         actionBlock:^{
                                             [weakSelf clearHistoryLogs];
                                         }]];
    [contents addSection:historyLogsSection];

    self.contents = contents;
}

#pragma mark - Events

- (void)showBlocklist
{
    BlockListViewController *vc = [BlockListViewController new];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)clearHistoryLogs
{
    ActionSheetController *alert =
        [[ActionSheetController alloc] initWithTitle:nil
                                             message:NSLocalizedString(@"SETTINGS_DELETE_HISTORYLOG_CONFIRMATION",
                                                         @"Alert message before user confirms clearing history")];

    [alert addAction:[OWSActionSheets cancelAction]];

    ActionSheetAction *deleteAction = [[ActionSheetAction
        alloc] initWithTitle:NSLocalizedString(@"SETTINGS_DELETE_HISTORYLOG_CONFIRMATION_BUTTON",
                                 @"Confirmation text for button which deletes all message, calling, attachments, etc.")
        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"delete")
                          style:ActionSheetActionStyleDestructive
                        handler:^(ActionSheetAction *_Nonnull action) {
                            [self deleteThreadsAndMessages];
                        }];
    [alert addAction:deleteAction];

    [self presentActionSheet:alert];
}

- (void)deleteThreadsAndMessages
{
    [ThreadUtil deleteAllContent];
}

- (void)didToggleScreenSecuritySwitch:(UISwitch *)sender
{
    BOOL enabled = sender.isOn;
    OWSLogInfo(@"toggled screen security: %@", enabled ? @"ON" : @"OFF");
    [self.preferences setScreenSecurity:enabled];
}

- (void)didToggleReadReceiptsSwitch:(UISwitch *)sender
{
    BOOL enabled = sender.isOn;
    OWSLogInfo(@"toggled areReadReceiptsEnabled: %@", enabled ? @"ON" : @"OFF");
    [self.readReceiptManager setAreReadReceiptsEnabledWithSneakyTransactionAndSyncConfiguration:enabled];
}

- (void)didToggleTypingIndicatorsSwitch:(UISwitch *)sender
{
    BOOL enabled = sender.isOn;
    OWSLogInfo(@"toggled areTypingIndicatorsEnabled: %@", enabled ? @"ON" : @"OFF");
    [self.typingIndicators setTypingIndicatorsEnabledAndSendSyncMessageWithValue:enabled];
}

- (void)didToggleCallsHideIPAddressSwitch:(UISwitch *)sender
{
    BOOL enabled = sender.isOn;
    OWSLogInfo(@"toggled callsHideIPAddress: %@", enabled ? @"ON" : @"OFF");
    [self.preferences setDoCallsHideIPAddress:enabled];
}

- (void)didToggleEnableSystemCallLogSwitch:(UISwitch *)sender
{
    OWSLogInfo(@"user toggled call kit preference: %@", (sender.isOn ? @"ON" : @"OFF"));
    [self.preferences setIsSystemCallLogEnabled:sender.isOn];

    // rebuild callUIAdapter since CallKit configuration changed.
    [AppEnvironment.shared.callService.individualCallService createCallUIAdapter];
}

- (void)didToggleUDUnrestrictedAccessSwitch:(UISwitch *)sender
{
    OWSLogInfo(@"toggled to: %@", (sender.isOn ? @"ON" : @"OFF"));
    [self.udManager setShouldAllowUnrestrictedAccessLocal:sender.isOn];
}

- (void)didToggleUDShowIndicatorsSwitch:(UISwitch *)sender
{
    OWSLogInfo(@"toggled to: %@", (sender.isOn ? @"ON" : @"OFF"));
    [self.preferences setShouldShowUnidentifiedDeliveryIndicatorsAndSendSyncMessage:sender.isOn];
}

- (void)didToggleLinkPreviewsEnabled:(UISwitch *)sender
{
    OWSLogInfo(@"toggled to: %@", (sender.isOn ? @"ON" : @"OFF"));
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [ExperienceUpgradeManager clearExperienceUpgrade:OWSObjcExperienceUpgradeIdLinkPreviews
                                             transaction:transaction.unwrapGrdbWrite];
        [SSKPreferences setAreLinkPreviewsEnabled:sender.isOn sendSyncMessage:YES transaction:transaction];
    });
}

- (void)showChangePin
{
    OWSLogInfo(@"");

    __weak PrivacySettingsTableViewController *weakSelf = self;
    OWSPinSetupViewController *vc = [OWSPinSetupViewController
        changingWithCompletionHandler:^(OWSPinSetupViewController *pinSetupVC, NSError *_Nullable error) {
            [weakSelf.navigationController popToViewController:weakSelf animated:YES];
        }];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showCreatePin
{
    OWSLogInfo(@"");

    __weak PrivacySettingsTableViewController *weakSelf = self;
    OWSPinSetupViewController *vc = [OWSPinSetupViewController
        creatingWithCompletionHandler:^(OWSPinSetupViewController *pinSetupVC, NSError *_Nullable error) {
            [weakSelf.navigationController setNavigationBarHidden:NO animated:NO];
            [weakSelf.navigationController popToViewController:weakSelf animated:YES];
        }];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)isRegistrationLockV2EnabledDidChange:(UISwitch *)sender
{
    BOOL shouldBeEnabled = sender.isOn;

    if (shouldBeEnabled == OWS2FAManager.shared.isRegistrationLockV2Enabled) {
        OWSLogInfo(@"ignoring redundant 2fa change.");
        return;
    }

    ActionSheetController *actionSheet;

    if (shouldBeEnabled) {
        actionSheet = [[ActionSheetController alloc]
            initWithTitle:NSLocalizedString(@"SETTINGS_REGISTRATION_LOCK_TURN_ON_TITLE",
                              @"Title for the alert confirming that the user wants to turn on registration lock.")
                  message:NSLocalizedString(@"SETTINGS_REGISTRATION_LOCK_TURN_ON_MESSAGE",
                              @"Body for the alert confirming that the user wants to turn on registration lock.")];

        ActionSheetAction *turnOnAction = [[ActionSheetAction alloc]
            initWithTitle:NSLocalizedString(
                              @"SETTINGS_REGISTRATION_LOCK_TURN_ON", @"Action to turn on registration lock")
                    style:ActionSheetActionStyleDefault
                  handler:^(ActionSheetAction *action) {
                      // If we don't have a PIN yet, we need to create one.
                      if (!OWS2FAManager.shared.is2FAEnabled) {
                          __weak PrivacySettingsTableViewController *weakSelf = self;
                          OWSPinSetupViewController *vc =
                              [OWSPinSetupViewController creatingRegistrationLockWithCompletionHandler:^(
                                  OWSPinSetupViewController *pinSetupVC, NSError *_Nullable error) {
                                  [weakSelf.navigationController setNavigationBarHidden:NO animated:NO];
                                  [weakSelf.navigationController popToViewController:weakSelf animated:YES];
                              }];
                          [self.navigationController pushViewController:vc animated:YES];
                      } else {
                          [OWS2FAManager.shared enableRegistrationLockV2]
                              .then(^{ [self updateTableContents]; })
                              .catch(^(NSError *error) { OWSLogError(@"Error: %@", error); });
                      }
                  }];
        [actionSheet addAction:turnOnAction];
    } else {
        actionSheet = [[ActionSheetController alloc]
            initWithTitle:NSLocalizedString(@"SETTINGS_REGISTRATION_LOCK_TURN_OFF_TITLE",
                              @"Title for the alert confirming that the user wants to turn off registration lock.")
                  message:nil];

        ActionSheetAction *turnOffAction =
            [[ActionSheetAction alloc] initWithTitle:NSLocalizedString(@"SETTINGS_REGISTRATION_LOCK_TURN_OFF",
                                                         @"Action to turn off registration lock")
                                               style:ActionSheetActionStyleDestructive
                                             handler:^(ActionSheetAction *action) {
                                                 [OWS2FAManager.shared disableRegistrationLockV2]
                                                     .then(^{ [self updateTableContents]; })
                                                     .catch(^(NSError *error) { OWSLogError(@"Error: %@", error); });
                                             }];
        [actionSheet addAction:turnOffAction];
    }

    ActionSheetAction *cancelAction = [[ActionSheetAction alloc] initWithTitle:CommonStrings.cancelButton
                                                                         style:ActionSheetActionStyleCancel
                                                                       handler:^(ActionSheetAction *action) {
                                                                           [sender setOn:!shouldBeEnabled animated:YES];
                                                                       }];

    [actionSheet addAction:cancelAction];
    [self presentActionSheet:actionSheet];
}

- (void)arePINRemindersEnabledDidChange:(UISwitch *)sender
{
    if (sender.isOn) {
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            [OWS2FAManager.shared setAreRemindersEnabled:YES transaction:transaction];
        });
    } else {
        OWSPinConfirmationViewController *pinConfirmationVC = [[OWSPinConfirmationViewController alloc]
                initWithTitle:NSLocalizedString(@"SETTINGS_PIN_REMINDER_DISABLE_CONFIRMATION_TITLE",
                                  @"The title for the dialog asking user to confirm their PIN to disable reminders".)
                  explanation:
                      NSLocalizedString(@"SETTINGS_PIN_REMINDER_DISABLE_CONFIRMATION_EXPLANATION",
                          @"The explanation for the dialog asking user to confirm their PIN to disable reminders".)
                   actionText:
                       NSLocalizedString(@"SETTINGS_PIN_REMINDER_DISABLE_CONFIRMATION_ACTION",
                           @"The button text for the dialog asking user to confirm their PIN to disable reminders".)
            completionHandler:^(BOOL confirmed) {
                if (confirmed) {
                    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                        [OWS2FAManager.shared setAreRemindersEnabled:NO transaction:transaction];
                    });

                    [ExperienceUpgradeManager dismissPINReminderIfNecessary];
                } else {
                    [self updateTableContents];
                }
            }];
        [self presentViewController:pinConfirmationVC animated:YES completion:nil];
    }
}

- (void)isScreenLockEnabledDidChange:(UISwitch *)sender
{
    BOOL shouldBeEnabled = sender.isOn;

    if (shouldBeEnabled == OWSScreenLock.shared.isScreenLockEnabled) {
        OWSLogInfo(@"ignoring redundant screen lock.");
        return;
    }

    OWSLogInfo(@"trying to set is screen lock enabled: %@", @(shouldBeEnabled));

    [OWSScreenLock.shared setIsScreenLockEnabled:shouldBeEnabled];
}

- (void)screenLockDidChange:(NSNotification *)notification
{
    OWSLogInfo(@"");

    [self updateTableContents];
}

- (void)showScreenLockTimeoutUI
{
    OWSLogInfo(@"");

    ActionSheetController *alert = [[ActionSheetController alloc]
        initWithTitle:NSLocalizedString(@"SETTINGS_SCREEN_LOCK_ACTIVITY_TIMEOUT",
                          @"Label for the 'screen lock activity timeout' setting of the privacy settings.")
              message:nil];
    for (NSNumber *timeoutValue in OWSScreenLock.shared.screenLockTimeouts) {
        uint32_t screenLockTimeout = (uint32_t)round(timeoutValue.doubleValue);
        NSString *screenLockTimeoutString = [self formatScreenLockTimeout:screenLockTimeout useShortFormat:NO];

        ActionSheetAction *action = [[ActionSheetAction alloc]
                      initWithTitle:screenLockTimeoutString
            accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.timeout.%@", timeoutValue]
                              style:ActionSheetActionStyleDefault
                            handler:^(ActionSheetAction *ignore) {
                                [OWSScreenLock.shared setScreenLockTimeout:screenLockTimeout];
                            }];
        [alert addAction:action];
    }
    [alert addAction:[OWSActionSheets cancelAction]];
    UIViewController *fromViewController = [[UIApplication sharedApplication] frontmostViewController];
    [fromViewController presentActionSheet:alert];
}

- (NSString *)formatScreenLockTimeout:(NSInteger)value useShortFormat:(BOOL)useShortFormat
{
    if (value <= 1) {
        return NSLocalizedString(@"SCREEN_LOCK_ACTIVITY_TIMEOUT_NONE",
            @"Indicates a delay of zero seconds, and that 'screen lock activity' will timeout immediately.");
    }
    return [NSString formatDurationSeconds:(uint32_t)value useShortFormat:useShortFormat];
}

- (void)configurationSettingsDidChange:(NSNotification *)notification
{
    OWSLogInfo(@"");

    [self updateTableContents];
}

@end

NS_ASSUME_NONNULL_END
