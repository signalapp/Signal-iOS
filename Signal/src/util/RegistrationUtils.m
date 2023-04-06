//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "RegistrationUtils.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/SignalCoreKit-Swift.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

@implementation RegistrationUtils

+ (void)showRelinkingUI
{
    OWSLogInfo(@"showRelinkingUI");

    if (![self.tsAccountManager resetForReregistration]) {
        OWSFailDebug(@"could not reset for re-registration.");
        return;
    }

    [Environment.shared.preferences unsetRecordedAPNSTokens];

    [Deprecated_ProvisioningController presentRelinkingFlow];
}

+ (void)showReregistrationUIFromViewController:(UIViewController *)fromViewController
{
    // If this is not the primary device, jump directly to the re-linking flow.
    if (!self.tsAccountManager.isPrimaryDevice) {
        [self showRelinkingUI];
        return;
    }

    ActionSheetController *actionSheet = [ActionSheetController new];

    [actionSheet
        addAction:[[ActionSheetAction alloc]
                      initWithTitle:NSLocalizedString(@"DEREGISTRATION_REREGISTER_WITH_SAME_PHONE_NUMBER",
                                        @"Label for button that lets users re-register using the same phone number.")
                              style:ActionSheetActionStyleDestructive
                            handler:^(ActionSheetAction *action) {
                                OWSLogInfo(@"Reregistering from banner");
                                [RegistrationUtils reregisterFromViewController:fromViewController];
                            }]];

    [actionSheet addAction:[OWSActionSheets cancelAction]];

    [fromViewController presentActionSheet:actionSheet];
}

@end

NS_ASSUME_NONNULL_END
