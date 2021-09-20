//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "RegistrationUtils.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/SignalCoreKit-Swift.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalUI/OWSNavigationController.h>

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

    [ProvisioningController presentRelinkingFlow];
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
                                [RegistrationUtils reregisterFromViewController:fromViewController];
                            }]];

    [actionSheet addAction:[OWSActionSheets cancelAction]];

    [fromViewController presentActionSheet:actionSheet];
}

@end

NS_ASSUME_NONNULL_END
