//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "CodeVerificationViewController.h"
#import "OWS2FARegistrationViewController.h"
#import "ProfileViewController.h"
#import "Signal-Swift.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalMessaging/UIViewController+OWS.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSNetworkManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface CodeVerificationViewController () <UITextFieldDelegate>

@property (nonatomic, readonly) AccountManager *accountManager;

// Where the user enters the verification code they wish to document
@property (nonatomic) UITextField *challengeTextField;

@property (nonatomic) UILabel *phoneNumberLabel;

//// User action buttons
@property (nonatomic) OWSFlatButton *submitButton;
@property (nonatomic) UIButton *sendCodeViaSMSAgainButton;
@property (nonatomic) UIButton *sendCodeViaVoiceButton;

@property (nonatomic) UIActivityIndicatorView *submitCodeSpinner;
@property (nonatomic) UIActivityIndicatorView *requestCodeAgainSpinner;
@property (nonatomic) UIActivityIndicatorView *requestCallSpinner;

@end

#pragma mark -

@implementation CodeVerificationViewController

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

    self.shouldUseTheme = NO;

    [self createViews];

    [self initializeKeyboardHandlers];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self enableServerActions:YES];
    [self updatePhoneNumberLabel];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [_challengeTextField becomeFirstResponder];
}

#pragma mark -

- (void)createViews
{
    self.view.backgroundColor = [UIColor whiteColor];
    self.view.opaque = YES;

    UIColor *signalBlueColor = [UIColor ows_signalBrandBlueColor];

    UIView *header = [UIView new];
    header.backgroundColor = signalBlueColor;
    [self.view addSubview:header];
    [header autoPinWidthToSuperview];
    [header autoPinEdgeToSuperviewEdge:ALEdgeTop];
    // The header will grow to accomodate the titleLabel's height.

    UILabel *titleLabel = [UILabel new];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.text = [self phoneNumberText];
    titleLabel.font = [UIFont ows_mediumFontWithSize:20.f];
    [header addSubview:titleLabel];
    [titleLabel autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [titleLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [titleLabel autoSetDimension:ALDimensionHeight toSize:40];
    [titleLabel autoHCenterInSuperview];

    // This view is used in more than one context.
    //
    // * Usually, it is pushed atop RegistrationViewController in which
    //   case we want a "back" button.
    // * It can also be used to re-register from the app's "de-registration"
    //   views, in which case RegistrationViewController is not used and we
    //   do _not_ want a "back" button.
    if (self.navigationController.viewControllers.count > 1) {
        UIButton *backButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [backButton
            setTitle:NSLocalizedString(@"VERIFICATION_BACK_BUTTON", @"button text for back button on verification view")
            forState:UIControlStateNormal];
        [backButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        backButton.titleLabel.font = [UIFont ows_mediumFontWithSize:14.f];
        [header addSubview:backButton];
        [backButton autoPinLeadingToSuperviewMarginWithInset:10.f];
        [backButton autoAlignAxis:ALAxisHorizontal toSameAxisOfView:titleLabel];
        [backButton addTarget:self action:@selector(backButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    }

    _phoneNumberLabel = [UILabel new];
    _phoneNumberLabel.textColor = [UIColor ows_darkGrayColor];
    _phoneNumberLabel.font = [UIFont ows_regularFontWithSize:20.f];
    _phoneNumberLabel.numberOfLines = 2;
    _phoneNumberLabel.adjustsFontSizeToFitWidth = YES;
    _phoneNumberLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_phoneNumberLabel];
    [_phoneNumberLabel autoPinWidthToSuperviewWithMargin:ScaleFromIPhone5(32)];
    [_phoneNumberLabel autoPinEdge:ALEdgeTop
                            toEdge:ALEdgeBottom
                            ofView:header
                        withOffset:ScaleFromIPhone5To7Plus(30, 100)];

    const CGFloat kHMargin = 36;

    if (UIDevice.currentDevice.isShorterThanIPhone5) {
        _challengeTextField = [DismissableTextField new];
    } else {
        _challengeTextField = [OWSTextField new];
    }

    _challengeTextField.textColor = [UIColor blackColor];
    _challengeTextField.placeholder = NSLocalizedString(@"VERIFICATION_CHALLENGE_DEFAULT_TEXT",
        @"Text field placeholder for SMS verification code during registration");
    _challengeTextField.font = [UIFont ows_lightFontWithSize:21.f];
    _challengeTextField.textAlignment = NSTextAlignmentCenter;
    _challengeTextField.keyboardType = UIKeyboardTypeNumberPad;
    _challengeTextField.delegate = self;
    [self.view addSubview:_challengeTextField];
    [_challengeTextField autoPinWidthToSuperviewWithMargin:kHMargin];
    [_challengeTextField autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:_phoneNumberLabel withOffset:25];

    UIView *underscoreView = [UIView new];
    underscoreView.backgroundColor = [UIColor colorWithWhite:0.5 alpha:1.f];
    [self.view addSubview:underscoreView];
    [underscoreView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:_challengeTextField withOffset:3];
    [underscoreView autoPinWidthToSuperviewWithMargin:kHMargin];
    [underscoreView autoSetDimension:ALDimensionHeight toSize:1.f];

    const CGFloat kSubmitButtonHeight = 47.f;
    // NOTE: We use ows_signalBrandBlueColor instead of ows_materialBlueColor
    //       throughout the onboarding flow to be consistent with the headers.
    OWSFlatButton *submitButton =
        [OWSFlatButton buttonWithTitle:NSLocalizedString(@"VERIFICATION_CHALLENGE_SUBMIT_CODE",
                                           @"button text during registration to submit your SMS verification code.")
                                  font:[OWSFlatButton fontForHeight:kSubmitButtonHeight]
                            titleColor:[UIColor whiteColor]
                       backgroundColor:[UIColor ows_signalBrandBlueColor]
                                target:self
                              selector:@selector(submitVerificationCode)];
    self.submitButton = submitButton;
    [self.view addSubview:_submitButton];
    [_submitButton autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:underscoreView withOffset:15];
    [_submitButton autoPinWidthToSuperviewWithMargin:kHMargin];
    [_submitButton autoSetDimension:ALDimensionHeight toSize:kSubmitButtonHeight];

    const CGFloat kSpinnerSize = 20;
    const CGFloat kSpinnerSpacing = ScaleFromIPhone5To7Plus(5, 15);

    _submitCodeSpinner =
        [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    [_submitButton addSubview:_submitCodeSpinner];
    [_submitCodeSpinner autoSetDimension:ALDimensionWidth toSize:kSpinnerSize];
    [_submitCodeSpinner autoSetDimension:ALDimensionHeight toSize:kSpinnerSize];
    [_submitCodeSpinner autoVCenterInSuperview];
    [_submitCodeSpinner autoPinTrailingToSuperviewMarginWithInset:kSpinnerSpacing];

    _sendCodeViaSMSAgainButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _sendCodeViaSMSAgainButton.backgroundColor = [UIColor whiteColor];
    [_sendCodeViaSMSAgainButton setTitle:NSLocalizedString(@"VERIFICATION_CHALLENGE_SUBMIT_AGAIN",
                                             @"button text during registration to request another SMS code be sent")
                                forState:UIControlStateNormal];
    [_sendCodeViaSMSAgainButton setTitleColor:signalBlueColor forState:UIControlStateNormal];
    _sendCodeViaSMSAgainButton.titleLabel.font = [UIFont ows_mediumFontWithSize:14.f];
    [_sendCodeViaSMSAgainButton addTarget:self
                                   action:@selector(sendCodeViaSMSAction:)
                         forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_sendCodeViaSMSAgainButton];
    [_sendCodeViaSMSAgainButton autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:_submitButton withOffset:10];
    [_sendCodeViaSMSAgainButton autoPinWidthToSuperviewWithMargin:kHMargin];
    [_sendCodeViaSMSAgainButton autoSetDimension:ALDimensionHeight toSize:35];

    _requestCodeAgainSpinner =
        [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [_sendCodeViaSMSAgainButton addSubview:_requestCodeAgainSpinner];
    [_requestCodeAgainSpinner autoSetDimension:ALDimensionWidth toSize:kSpinnerSize];
    [_requestCodeAgainSpinner autoSetDimension:ALDimensionHeight toSize:kSpinnerSize];
    [_requestCodeAgainSpinner autoVCenterInSuperview];
    [_requestCodeAgainSpinner autoPinTrailingToSuperviewMarginWithInset:kSpinnerSpacing];

    _sendCodeViaVoiceButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _sendCodeViaVoiceButton.backgroundColor = [UIColor whiteColor];
    [_sendCodeViaVoiceButton
        setTitle:NSLocalizedString(@"VERIFICATION_CHALLENGE_SEND_VIA_VOICE",
                     @"button text during registration to request phone number verification be done via phone call")
        forState:UIControlStateNormal];
    [_sendCodeViaVoiceButton setTitleColor:signalBlueColor forState:UIControlStateNormal];
    _sendCodeViaVoiceButton.titleLabel.font = [UIFont ows_mediumFontWithSize:14.f];
    [_sendCodeViaVoiceButton addTarget:self
                                action:@selector(sendCodeViaVoiceAction:)
                      forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_sendCodeViaVoiceButton];
    [_sendCodeViaVoiceButton autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:_sendCodeViaSMSAgainButton];
    [_sendCodeViaVoiceButton autoPinWidthToSuperviewWithMargin:kHMargin];
    [_sendCodeViaVoiceButton autoSetDimension:ALDimensionHeight toSize:35];

    _requestCallSpinner =
        [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [_sendCodeViaVoiceButton addSubview:_requestCallSpinner];
    [_requestCallSpinner autoSetDimension:ALDimensionWidth toSize:kSpinnerSize];
    [_requestCallSpinner autoSetDimension:ALDimensionHeight toSize:kSpinnerSize];
    [_requestCallSpinner autoVCenterInSuperview];
    [_requestCallSpinner autoPinTrailingToSuperviewMarginWithInset:kSpinnerSpacing];
}

- (NSString *)phoneNumberText
{
    OWSAssertDebug([TSAccountManager localNumber] != nil);
    return [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:[TSAccountManager localNumber]];
}

- (void)updatePhoneNumberLabel
{
    _phoneNumberLabel.text =
        [NSString stringWithFormat:NSLocalizedString(@"VERIFICATION_PHONE_NUMBER_FORMAT",
                                       @"Label indicating the phone number currently being verified."),
                  [self phoneNumberText]];
}

- (void)startActivityIndicator
{
    [self.submitCodeSpinner startAnimating];
    [self enableServerActions:NO];
    [self.challengeTextField resignFirstResponder];
}

- (void)stopActivityIndicator
{
    [self enableServerActions:YES];
    [self.submitCodeSpinner stopAnimating];
}

- (void)submitVerificationCode
{
    [self startActivityIndicator];
    OWSProdInfo([OWSAnalyticsEvents registrationRegisteringCode]);
    __weak CodeVerificationViewController *weakSelf = self;
    [self.accountManager registerWithVerificationCode:[self validationCodeFromTextField] pin:nil]
        .then(^{
            OWSProdInfo([OWSAnalyticsEvents registrationRegisteringSubmittedCode]);

            OWSLogInfo(@"Successfully registered Signal account.");
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf stopActivityIndicator];
                [weakSelf verificationWasCompleted];
            });
        })
        .catch(^(NSError *error) {
            OWSLogError(@"error: %@, %@, %zd", [error class], error.domain, error.code);
            OWSProdInfo([OWSAnalyticsEvents registrationRegistrationFailed]);
            OWSLogError(@"error verifying challenge: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf stopActivityIndicator];

                if ([error.domain isEqualToString:OWSSignalServiceKitErrorDomain]
                    && error.code == OWSErrorCodeRegistrationMissing2FAPIN) {
                    CodeVerificationViewController *strongSelf = weakSelf;
                    if (!strongSelf) {
                        return;
                    }
                    OWSLogInfo(@"Showing 2FA registration view.");
                    OWS2FARegistrationViewController *viewController = [OWS2FARegistrationViewController new];
                    viewController.verificationCode = strongSelf.validationCodeFromTextField;
                    [strongSelf.navigationController pushViewController:viewController animated:YES];
                } else {
                    [weakSelf presentAlertWithVerificationError:error];
                    [weakSelf.challengeTextField becomeFirstResponder];
                }
            });
        });
}

- (void)verificationWasCompleted
{
    [ProfileViewController presentForRegistration:self.navigationController];
}

- (void)presentAlertWithVerificationError:(NSError *)error
{
    UIAlertController *alert;
    alert = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"REGISTRATION_VERIFICATION_FAILED_TITLE", @"Alert view title")
                         message:error.localizedDescription
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:CommonStrings.dismissButton
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                                [self.challengeTextField becomeFirstResponder];
                                            }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)validationCodeFromTextField
{
    return [self.challengeTextField.text stringByReplacingOccurrencesOfString:@"-" withString:@""];
}

#pragma mark - Actions

- (void)sendCodeViaSMSAction:(id)sender
{
    OWSProdInfo([OWSAnalyticsEvents registrationRegisteringRequestedNewCodeBySms]);

    [self enableServerActions:NO];

    [_requestCodeAgainSpinner startAnimating];
    __weak CodeVerificationViewController *weakSelf = self;
    [TSAccountManager
        rerequestSMSWithSuccess:^{
            OWSLogInfo(@"Successfully requested SMS code");
            [weakSelf enableServerActions:YES];
            [weakSelf.requestCodeAgainSpinner stopAnimating];
        }
        failure:^(NSError *error) {
            OWSLogError(@"Failed to request SMS code with error: %@", error);
            [weakSelf showRegistrationErrorMessage:error];
            [weakSelf enableServerActions:YES];
            [weakSelf.requestCodeAgainSpinner stopAnimating];
            [weakSelf.challengeTextField becomeFirstResponder];
        }];
}

- (void)sendCodeViaVoiceAction:(id)sender
{
    OWSProdInfo([OWSAnalyticsEvents registrationRegisteringRequestedNewCodeByVoice]);

    [self enableServerActions:NO];

    [_requestCallSpinner startAnimating];
    __weak CodeVerificationViewController *weakSelf = self;
    [TSAccountManager
        rerequestVoiceWithSuccess:^{
            OWSLogInfo(@"Successfully requested voice code");

            [weakSelf enableServerActions:YES];
            [weakSelf.requestCallSpinner stopAnimating];
        }
        failure:^(NSError *error) {
            OWSLogError(@"Failed to request voice code with error: %@", error);
            [weakSelf showRegistrationErrorMessage:error];
            [weakSelf enableServerActions:YES];
            [weakSelf.requestCallSpinner stopAnimating];
            [weakSelf.challengeTextField becomeFirstResponder];
        }];
}

- (void)showRegistrationErrorMessage:(NSError *)registrationError
{
    [OWSAlerts showAlertWithTitle:registrationError.localizedDescription
                          message:registrationError.localizedRecoverySuggestion];
}

- (void)enableServerActions:(BOOL)enabled
{
    [_submitButton setEnabled:enabled];
    [_sendCodeViaSMSAgainButton setEnabled:enabled];
    [_sendCodeViaVoiceButton setEnabled:enabled];
}

- (void)backButtonPressed:(id)sender
{
    OWSProdInfo([OWSAnalyticsEvents registrationVerificationBack]);

    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Keyboard notifications

- (void)initializeKeyboardHandlers
{
    UITapGestureRecognizer *outsideTabRecognizer =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboardFromAppropriateSubView)];
    [self.view addGestureRecognizer:outsideTabRecognizer];
    self.view.userInteractionEnabled = YES;
}

- (void)dismissKeyboardFromAppropriateSubView
{
    [self.view endEditing:NO];
}

- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText
{

    // Verification codes take this form: "123-456".
    //
    // * We only want to let the user "6 decimal digits + 1 hyphen = 7".
    // * The user shouldn't have to enter the hyphen - it should be added automatically.
    // * The user should be able to copy and paste freely.
    // * Invalid input (including extraneous hyphens) should be simply ignored.
    //
    // We accomplish this by being permissive and trying to "take as much of the user
    // input as possible".
    //
    // * Always accept deletes.
    // * Ignore invalid input.
    // * Take partial input if possible.

    NSString *oldText = textField.text;
    // Construct the new contents of the text field by:
    // 1. Determining the "left" substring: the contents of the old text _before_ the deletion range.
    //    Filtering will remove non-decimal digit characters like hyphen "-".
    NSString *left = [oldText substringToIndex:range.location].digitsOnly;
    // 2. Determining the "right" substring: the contents of the old text _after_ the deletion range.
    NSString *right = [oldText substringFromIndex:range.location + range.length].digitsOnly;
    // 3. Determining the "center" substring: the contents of the new insertion text.
    NSString *center = insertionText.digitsOnly;
    // 3a. Trim the tail of the "center" substring to ensure that we don't end up
    //     with more than 6 decimal digits.
    while (center.length > 0 && left.length + center.length + right.length > 6) {
        center = [center substringToIndex:center.length - 1];
    }
    // 4. Construct the "raw" new text by concatenating left, center and right.
    NSString *rawNewText = [[left stringByAppendingString:center] stringByAppendingString:right];
    // 5. Construct the "formatted" new text by inserting a hyphen if necessary.
    NSString *formattedNewText
        = (rawNewText.length <= 3 ? rawNewText
                                  : [[[rawNewText substringToIndex:3] stringByAppendingString:@"-"]
                                        stringByAppendingString:[rawNewText substringFromIndex:3]]);
    textField.text = formattedNewText;

    // Move the cursor after the newly inserted text.
    NSUInteger newInsertionPoint = left.length + center.length;
    if (newInsertionPoint > 3) {
        // Nudge the cursor to the right to reflect the hyphen
        // if necessary.
        newInsertionPoint++;
    }
    UITextPosition *newPosition =
        [textField positionFromPosition:textField.beginningOfDocument offset:(NSInteger)newInsertionPoint];
    textField.selectedTextRange = [textField textRangeFromPosition:newPosition toPosition:newPosition];

    return NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [self submitVerificationCode];
    [textField resignFirstResponder];
    return NO;
}

- (void)setVerificationCodeAndTryToVerify:(NSString *)verificationCode
{
    NSString *rawNewText = verificationCode.digitsOnly;
    NSString *formattedNewText
        = (rawNewText.length <= 3 ? rawNewText
                                  : [[[rawNewText substringToIndex:3] stringByAppendingString:@"-"]
                                        stringByAppendingString:[rawNewText substringFromIndex:3]]);
    self.challengeTextField.text = formattedNewText;
    // Move the cursor after the newly inserted text.
    UITextPosition *newPosition = [self.challengeTextField endOfDocument];
    self.challengeTextField.selectedTextRange =
        [self.challengeTextField textRangeFromPosition:newPosition toPosition:newPosition];
    [self submitVerificationCode];
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

@end

NS_ASSUME_NONNULL_END
