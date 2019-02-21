//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "RegistrationUtils.h"
#import "OWSNavigationController.h"
#import "Signal-Swift.h"
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

#pragma mark -

+ (void)showReregistrationUIFromViewController:(UIViewController *)fromViewController
{
    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    [actionSheetController
        addAction:[UIAlertAction
                      actionWithTitle:NSLocalizedString(@"DEREGISTRATION_REREGISTER_WITH_SAME_PHONE_NUMBER",
                                          @"Label for button that lets users re-register using the same phone number.")
                                style:UIAlertActionStyleDestructive
                              handler:^(UIAlertAction *action) {
                                  [RegistrationUtils reregisterWithFromViewController:fromViewController];
                              }]];

    [actionSheetController addAction:[OWSAlerts cancelAction]];

    [fromViewController presentViewController:actionSheetController animated:YES completion:nil];
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
                      NSString *phoneNumber = self.tsAccountManager.reregisterationPhoneNumber;
                      [self.tsAccountManager registerWithPhoneNumber:phoneNumber
                          captchaToken:nil
                          success:^{
                              OWSLogInfo(@"re-registering: send verification code succeeded.");

                              dispatch_async(dispatch_get_main_queue(), ^{
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
                              });
                          }
                          failure:^(NSError *error) {
                              OWSLogError(@"re-registering: send verification code failed.");

                              dispatch_async(dispatch_get_main_queue(), ^{
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
                              });
                          }
                          smsVerification:YES];
                  }];
}

@end

NS_ASSUME_NONNULL_END
