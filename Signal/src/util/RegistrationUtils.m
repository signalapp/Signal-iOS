//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

+ (void)showReregistrationUIFromViewController:(UIViewController *)fromViewController
{
    UIAlertController *actionSheet =
        [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    [actionSheet
        addAction:[UIAlertAction
                      actionWithTitle:NSLocalizedString(@"DEREGISTRATION_REREGISTER_WITH_SAME_PHONE_NUMBER",
                                          @"Label for button that lets users re-register using the same phone number.")
                                style:UIAlertActionStyleDestructive
                              handler:^(UIAlertAction *action) {
                                  [RegistrationUtils reregisterWithFromViewController:fromViewController];
                              }]];

    [actionSheet addAction:[OWSAlerts cancelAction]];

    [fromViewController presentAlert:actionSheet];
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
                      [[self.accountManager requestAccountVerificationObjCWithRecipientId:phoneNumber
                                                                             captchaToken:nil
                                                                                    isSMS:true]
                              .then(^{
                                  OWSLogInfo(@"re-registering: send verification code succeeded.");

                                  [modalActivityIndicator dismissWithCompletion:^{
                                      OnboardingController *onboardingController = [OnboardingController new];
                                      OnboardingPhoneNumber *onboardingPhoneNumber =
                                          [[OnboardingPhoneNumber alloc] initWithE164:phoneNumber
                                                                            userInput:phoneNumber];
                                      [onboardingController updateWithPhoneNumber:onboardingPhoneNumber];
                                      OnboardingVerificationViewController *viewController =
                                          [[OnboardingVerificationViewController alloc]
                                              initWithOnboardingController:onboardingController];
                                      [viewController hideBackLink];
                                      OWSNavigationController *navigationController =
                                          [[OWSNavigationController alloc] initWithRootViewController:viewController];
                                      navigationController.navigationBarHidden = YES;

                                      [UIApplication sharedApplication].delegate.window.rootViewController
                                          = navigationController;
                                  }];
                              })
                              .catch(^(NSError *error) {
                                  OWSLogError(@"re-registering: send verification code failed.");
                                  [modalActivityIndicator dismissWithCompletion:^{
                                      if (error.code == 400) {
                                          [OWSAlerts showAlertWithTitle:NSLocalizedString(@"REGISTRATION_ERROR", nil)
                                                                message:NSLocalizedString(
                                                                            @"REGISTRATION_NON_VALID_NUMBER", nil)];
                                      } else {
                                          [OWSAlerts showAlertWithTitle:error.localizedDescription
                                                                message:error.localizedRecoverySuggestion];
                                      }
                                  }];
                              }) retainUntilComplete];
                  }];
}

@end

NS_ASSUME_NONNULL_END
