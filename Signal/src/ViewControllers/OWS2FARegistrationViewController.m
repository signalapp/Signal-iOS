//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWS2FARegistrationViewController.h"
#import "PinEntryView.h"
#import "ProfileViewController.h"
#import "Signal-Swift.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIViewController+OWS.h>
#import <SignalServiceKit/OWS2FAManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWS2FARegistrationViewController () <PinEntryViewDelegate>

@property (nonatomic, readonly) AccountManager *accountManager;
@property (nonatomic) PinEntryView *entryView;

@end

#pragma mark -

@implementation OWS2FARegistrationViewController

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    _accountManager = SignalApp.sharedApp.accountManager;

    return self;
}

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _accountManager = SignalApp.sharedApp.accountManager;

    return self;
}

#pragma mark - View Lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

    // The navigation bar is hidden in the registration workflow.
    if (self.navigationController.navigationBarHidden) {
        [self.navigationController setNavigationBarHidden:NO animated:YES];
    }
    self.navigationItem.hidesBackButton = YES;

    self.title = NSLocalizedString(@"REGISTRATION_ENTER_LOCK_PIN_NAV_TITLE",
        @"Navigation title shown when user is re-registering after having enabled registration lock");

    self.view.backgroundColor = [Theme backgroundColor];

    PinEntryView *entryView = [PinEntryView new];
    self.entryView = entryView;
    entryView.delegate = self;
    [self.view addSubview:entryView];

    entryView.instructionsText = NSLocalizedString(
        @"REGISTER_2FA_INSTRUCTIONS", @"Instructions to enter the 'two-factor auth pin' in the 2FA registration view.");

    // Layout
    [entryView autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [entryView autoPinEdgeToSuperviewMargin:ALEdgeLeft];
    [entryView autoPinEdgeToSuperviewMargin:ALEdgeRight];
    [entryView autoPinToBottomLayoutGuideOfViewController:self withInset:0];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [self.entryView makePinTextFieldFirstResponder];
}

#pragma mark - PinEntryViewDelegate

- (void)pinEntryView:(PinEntryView *)entryView submittedPinCode:(NSString *)pinCode
{
    OWSAssertDebug(self.entryView.hasValidPin);

    [self tryToRegisterWithPinCode:pinCode];
}

- (void)pinEntryViewForgotPinLinkTapped:(PinEntryView *)entryView
{
    NSString *alertBody = NSLocalizedString(@"REGISTER_2FA_FORGOT_PIN_ALERT_MESSAGE",
        @"Alert message explaining what happens if you forget your 'two-factor auth pin'.");
    [OWSAlerts showAlertWithTitle:nil message:alertBody];
}

#pragma mark - Registration

- (void)tryToRegisterWithPinCode:(NSString *)pinCode
{
    OWSAssertDebug(self.entryView.hasValidPin);
    OWSAssertDebug(self.verificationCode.length > 0);
    OWSAssertDebug(pinCode.length > 0);

    OWSLogInfo(@"");

    __weak OWS2FARegistrationViewController *weakSelf = self;

    [ModalActivityIndicatorViewController
        presentFromViewController:self
                        canCancel:NO
                  backgroundBlock:^(ModalActivityIndicatorViewController *modalActivityIndicator) {
                      OWSProdInfo([OWSAnalyticsEvents registrationRegisteringCode]);
                      [self.accountManager registerWithVerificationCode:self.verificationCode pin:pinCode]
                          .then(^{
                              OWSAssertIsOnMainThread();
                              OWSProdInfo([OWSAnalyticsEvents registrationRegisteringSubmittedCode]);
                              [[OWS2FAManager sharedManager] mark2FAAsEnabledWithPin:pinCode];

                              OWSLogInfo(@"Successfully registered Signal account.");
                              dispatch_async(dispatch_get_main_queue(), ^{
                                  [modalActivityIndicator dismissWithCompletion:^{
                                      OWSAssertIsOnMainThread();

                                      [weakSelf verificationWasCompleted];
                                  }];
                              });
                          })
                          .catch(^(NSError *error) {
                              OWSAssertIsOnMainThread();
                              OWSProdInfo([OWSAnalyticsEvents registrationRegistrationFailed]);
                              OWSLogError(@"error verifying challenge: %@", error);
                              dispatch_async(dispatch_get_main_queue(), ^{
                                  [modalActivityIndicator dismissWithCompletion:^{
                                      OWSAssertIsOnMainThread();

                                      [OWSAlerts showAlertWithTitle:NSLocalizedString(
                                                                        @"REGISTER_2FA_REGISTRATION_FAILED_ALERT_TITLE",
                                                                        @"Title for alert indicating that attempt to "
                                                                        @"register with 'two-factor auth' failed.")
                                                            message:error.localizedDescription];

                                      [weakSelf.entryView makePinTextFieldFirstResponder];
                                  }];
                              });
                          });
                  }];
}

- (void)verificationWasCompleted
{
    [ProfileViewController presentForRegistration:self.navigationController];
}

@end

NS_ASSUME_NONNULL_END
