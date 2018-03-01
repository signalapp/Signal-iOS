//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWS2FARegistrationViewController.h"
#import "ProfileViewController.h"
#import "Signal-Swift.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalMessaging/UIColor+OWS.h>
#import <SignalMessaging/UIFont+OWS.h>
#import <SignalMessaging/UIView+OWS.h>
#import <SignalMessaging/UIViewController+OWS.h>
#import <SignalServiceKit/OWS2FAManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWS2FARegistrationViewController () <UITextFieldDelegate>

@property (nonatomic, readonly) AccountManager *accountManager;

@property (nonatomic) UITextField *pinTextfield;

@property (nonatomic) OWSFlatButton *submitButton;

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

    self.view.backgroundColor = UIColor.whiteColor;

    [self createContents];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self updateEnabling];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    // If we're using a PIN textfield, select it.
    [self.pinTextfield becomeFirstResponder];
}

- (UILabel *)createLabelWithText:(NSString *)text
{
    UILabel *label = [UILabel new];
    label.textColor = [UIColor blackColor];
    label.text = text;
    label.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(14.f, 16.f)];
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:label];
    return label;
}

- (void)createPinTextfield
{
    self.pinTextfield = [UITextField new];
    self.pinTextfield.textColor = [UIColor blackColor];
    self.pinTextfield.placeholder
        = NSLocalizedString(@"2FA_PIN_DEFAULT_TEXT", @"Text field placeholder when entering a 'two-factor auth pin'.");
    self.pinTextfield.font = [UIFont ows_mediumFontWithSize:ScaleFromIPhone5To7Plus(30.f, 36.f)];
    self.pinTextfield.textAlignment = NSTextAlignmentCenter;
    self.pinTextfield.keyboardType = UIKeyboardTypeNumberPad;
    self.pinTextfield.delegate = self;
    self.pinTextfield.secureTextEntry = YES;
    self.pinTextfield.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.pinTextfield];
}

- (UILabel *)createForgotLink
{
    UILabel *label = [UILabel new];
    label.textColor = [UIColor ows_materialBlueColor];
    NSString *text = NSLocalizedString(
        @"REGISTER_2FA_FORGOT_PIN", @"Label for 'I forgot my PIN' link in the 2FA registration view.");
    label.attributedText = [[NSAttributedString alloc]
        initWithString:text
            attributes:@{
                NSForegroundColorAttributeName : [UIColor ows_materialBlueColor],
                NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid)
            }];
    label.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(14.f, 16.f)];
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.textAlignment = NSTextAlignmentCenter;
    label.userInteractionEnabled = YES;
    [label addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                        action:@selector(forgotPinLinkTapped:)]];
    [self.view addSubview:label];
    return label;
}

- (void)createSubmitButton
{
    const CGFloat kSubmitButtonHeight = 47.f;
    // NOTE: We use ows_signalBrandBlueColor instead of ows_materialBlueColor
    //       throughout the onboarding flow to be consistent with the headers.
    OWSFlatButton *submitButton =
        [OWSFlatButton buttonWithTitle:NSLocalizedString(@"REGISTER_2FA_SUBMIT_BUTTON",
                                           @"Label for 'submit' button in the 2FA registration view.")
                                  font:[OWSFlatButton fontForHeight:kSubmitButtonHeight]
                            titleColor:[UIColor whiteColor]
                       backgroundColor:[UIColor ows_signalBrandBlueColor]
                                target:self
                              selector:@selector(submitButtonWasPressed)];
    self.submitButton = submitButton;
    [self.view addSubview:self.submitButton];
    [self.submitButton autoSetDimension:ALDimensionHeight toSize:kSubmitButtonHeight];
}

- (CGFloat)hMargin
{
    return 20.f;
}

- (void)createContents
{
    const CGFloat kVSpacing = 30.f;

    NSString *instructionsText = NSLocalizedString(
        @"REGISTER_2FA_INSTRUCTIONS", @"Instructions to enter the 'two-factor auth pin' in the 2FA registration view.");
    UILabel *instructionsLabel = [self createLabelWithText:instructionsText];
    [instructionsLabel autoPinTopToSuperviewWithMargin:kVSpacing];
    [instructionsLabel autoPinWidthToSuperviewWithMargin:self.hMargin];

    UILabel *createForgotLink = [self createForgotLink];
    [createForgotLink autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:instructionsLabel withOffset:5];
    [createForgotLink autoPinWidthToSuperviewWithMargin:self.hMargin];

    [self createPinTextfield];
    [self.pinTextfield autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:createForgotLink withOffset:kVSpacing];
    [self.pinTextfield autoPinWidthToSuperviewWithMargin:self.hMargin];

    UIView *underscoreView = [UIView new];
    underscoreView.backgroundColor = [UIColor colorWithWhite:0.5 alpha:1.f];
    [self.view addSubview:underscoreView];
    [underscoreView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.pinTextfield withOffset:3];
    [underscoreView autoPinWidthToSuperviewWithMargin:self.hMargin];
    [underscoreView autoSetDimension:ALDimensionHeight toSize:1.f];

    [self createSubmitButton];
    [self.submitButton autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:underscoreView withOffset:kVSpacing];
    [self.submitButton autoPinWidthToSuperviewWithMargin:self.hMargin];

    [self updateEnabling];
}

- (void)updateEnabling
{
    [self.submitButton setEnabled:self.hasValidPin];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText
{

    [ViewControllerUtils ows2FAPINTextField:textField
              shouldChangeCharactersInRange:range
                          replacementString:insertionText];

    [self updateEnabling];

    return NO;
}

#pragma mark - Events

- (void)submitButtonWasPressed
{
    OWSAssert(self.hasValidPin);

    [self tryToRegister];
}

- (BOOL)hasValidPin
{
    return self.pinTextfield.text.length >= kMin2FAPinLength;
}

- (void)tryToRegister
{
    OWSAssert(self.hasValidPin);
    OWSAssert(self.verificationCode.length > 0);
    NSString *pin = self.pinTextfield.text;
    OWSAssert(pin.length > 0);

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    __weak OWS2FARegistrationViewController *weakSelf = self;

    [ModalActivityIndicatorViewController
        presentFromViewController:self
                        canCancel:NO
                  backgroundBlock:^(ModalActivityIndicatorViewController *modalActivityIndicator) {
                      OWSProdInfo([OWSAnalyticsEvents registrationRegisteringCode]);
                      [self.accountManager registerWithVerificationCode:self.verificationCode pin:pin]
                          .then(^{
                              OWSAssertIsOnMainThread();
                              OWSProdInfo([OWSAnalyticsEvents registrationRegisteringSubmittedCode]);

                              DDLogInfo(@"%@ Successfully registered Signal account.", weakSelf.logTag);
                              dispatch_async(dispatch_get_main_queue(), ^{
                                  [modalActivityIndicator dismissWithCompletion:^{
                                      OWSAssertIsOnMainThread();

                                      [weakSelf vericationWasCompleted];
                                  }];
                              });
                          })
                          .catch(^(NSError *error) {
                              OWSAssertIsOnMainThread();
                              OWSProdInfo([OWSAnalyticsEvents registrationRegistrationFailed]);
                              DDLogError(@"%@ error verifying challenge: %@", weakSelf.logTag, error);
                              dispatch_async(dispatch_get_main_queue(), ^{
                                  [modalActivityIndicator dismissWithCompletion:^{
                                      OWSAssertIsOnMainThread();

                                      [OWSAlerts
                                          showAlertWithTitle:NSLocalizedString(@"ALERT_ERROR_TITLE", @"")
                                                     message:NSLocalizedString(@"REGISTER_2FA_REGISTRATION_FAILED",
                                                                 @"Error indicating that attempt to register with "
                                                                 @"'two-factor "
                                                                 @"auth' failed.")];

                                      [weakSelf.pinTextfield becomeFirstResponder];
                                  }];
                              });
                          });
                  }];
}

- (void)vericationWasCompleted
{
    [ProfileViewController presentForRegistration:self.navigationController];
}

- (void)forgotPinLinkTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [OWSAlerts
            showAlertWithTitle:nil
                       message:NSLocalizedString(@"REGISTER_2FA_FORGOT_PIN_ALERT_MESSAGE",
                                   @"Alert message explaining what happens if you forget your 'two-factor auth pin'.")];
    }
}

@end

NS_ASSUME_NONNULL_END
