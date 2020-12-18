//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "RegistrationUtils.h"
#import "OWSNavigationController.h"
#import "Signal-Swift.h"
#import <PromiseKit/PromiseKit.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

@implementation RegistrationUtils

#pragma mark - Dependencies

+ (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);
    
    return SSKEnvironment.shared.tsAccountManager;
}

+ (AccountManager *)accountManager
{
    return AppEnvironment.shared.accountManager;
}

#pragma mark -

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
                                [RegistrationUtils reregisterWithFromViewController:fromViewController];
                            }]];

    [actionSheet addAction:[OWSActionSheets cancelAction]];

    [fromViewController presentActionSheet:actionSheet];
}

+ (void)reregisterWithFromViewController:(UIViewController *)fromViewController
{
    OWSLogInfo(@"reregisterWithSamePhoneNumber.");

    if (![self.tsAccountManager resetForReregistration]) {
        OWSFailDebug(@"could not reset for re-registration.");
        return;
    }

    [Environment.shared.preferences unsetRecordedAPNSTokens];

    [ModalActivityIndicatorViewController
        presentFromViewController:fromViewController
                        canCancel:NO
                  backgroundBlock:^(ModalActivityIndicatorViewController *modalActivityIndicator) {
                      NSString *phoneNumber = self.tsAccountManager.reregistrationPhoneNumber;
                      [self.accountManager requestAccountVerificationObjCWithRecipientId:phoneNumber
                                                                            captchaToken:nil
                                                                                   isSMS:true]
                          .then(^{
                              OWSAssertIsOnMainThread();

                              OWSLogInfo(@"re-registering: send verification code succeeded.");

                              [modalActivityIndicator dismissWithCompletion:^{
                                  OnboardingController *onboardingController = [OnboardingController new];
                                  OnboardingPhoneNumber *onboardingPhoneNumber =
                                      [[OnboardingPhoneNumber alloc] initWithE164:phoneNumber userInput:phoneNumber];
                                  [onboardingController updateWithPhoneNumber:onboardingPhoneNumber];


                                  OnboardingVerificationViewController *viewController =
                                      [[OnboardingVerificationViewController alloc]
                                          initWithOnboardingController:onboardingController];
                                  [viewController hideBackLink];
                                  OnboardingNavigationController *navigationController =
                                      [[OnboardingNavigationController alloc]
                                          initWithOnboardingController:onboardingController];
                                  [navigationController setViewControllers:@[ viewController ] animated:NO];
                                  navigationController.navigationBarHidden = YES;

                                  [UIApplication sharedApplication].delegate.window.rootViewController
                                      = navigationController;
                              }];
                          })
                          .catch(^(NSError *error) {
                              OWSAssertIsOnMainThread();

                              OWSLogError(@"re-registering: send verification code failed.");
                              [modalActivityIndicator dismissWithCompletion:^{
                                  if (error.code == 400) {
                                      [OWSActionSheets
                                          showActionSheetWithTitle:NSLocalizedString(@"REGISTRATION_ERROR", nil)
                                                           message:NSLocalizedString(
                                                                       @"REGISTRATION_NON_VALID_NUMBER", nil)];
                                  } else {
                                      [OWSActionSheets showActionSheetWithTitle:error.localizedDescription
                                                                        message:error.localizedRecoverySuggestion];
                                  }
                              }];
                          });
                  }];
}

@end

NS_ASSUME_NONNULL_END
