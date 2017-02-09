//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "CodeVerificationViewController.h"
#import "AppDelegate.h"
#import "RPAccountManager.h"
#import "Signal-Swift.h"
#import "SignalsNavigationController.h"
#import "SignalsViewController.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSStorageManager+keyingMaterial.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kCompletedRegistrationSegue = @"CompletedRegistration";

@interface CodeVerificationViewController () <UITextFieldDelegate>

@property (nonatomic, readonly) AccountManager *accountManager;

// Where the user enters the verification code they wish to document
@property (nonatomic) UITextField *challengeTextField;

@property (nonatomic) UILabel *phoneNumberLabel;

//// User action buttons
@property (nonatomic) UIButton *challengeButton;
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

    _accountManager = [Environment getCurrent].accountManager;

    return self;
}

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _accountManager = [Environment getCurrent].accountManager;

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self createViews];
    
    [self initializeKeyboardHandlers];
}

- (void)createViews {
    self.view.backgroundColor = [UIColor whiteColor];
    self.view.opaque = YES;

    // TODO: Move this to UIColor+OWS?
    UIColor *signalBlueColor = [UIColor colorWithRed:0.1135657504
                                               green:0.4787300229
                                                blue:0.89595204589999999
                                               alpha:1.];

    UIView *header = [UIView new];
    header.backgroundColor = signalBlueColor;
    [self.view addSubview:header];
    [header autoPinWidthToSuperview];
    [header autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [header autoSetDimension:ALDimensionHeight toSize:ScaleFromIPhone5To7Plus(60, 60)];

    UILabel *titleLabel = [UILabel new];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.text = NSLocalizedString(@"VERIFICATION_HEADER", @"Navigation title in the registration flow - during the sms code verification process.");
    titleLabel.font = [UIFont ows_mediumFontWithSize:20.f];
    [header addSubview:titleLabel];
    [titleLabel autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [titleLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [titleLabel autoHCenterInSuperview];

    UIButton *backButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [backButton setTitle:NSLocalizedString(@"VERIFICATION_BACK_BUTTON", @"button text for back button on verification view")
                     forState:UIControlStateNormal];
    [backButton setTitleColor:[UIColor whiteColor]
                          forState:UIControlStateNormal];
    backButton.titleLabel.font = [UIFont ows_mediumFontWithSize:14.f];
    [header addSubview:backButton];
    [backButton autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:ScaleFromIPhone5To7Plus(10, 10)];
    [backButton autoAlignAxis:ALAxisHorizontal toSameAxisOfView:titleLabel];
    [backButton addTarget:self action:@selector(backButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    
    _phoneNumberLabel = [UILabel new];
    _phoneNumberLabel.textColor = [UIColor ows_darkGrayColor];
    _phoneNumberLabel.font = [UIFont ows_regularFontWithSize:20.f];
    [self.view addSubview:_phoneNumberLabel];
    [_phoneNumberLabel autoHCenterInSuperview];
    [_phoneNumberLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:header
                          withOffset:ScaleFromIPhone5To7Plus(25, 100)];
    
    _challengeTextField = [UITextField new];
    _challengeTextField.textColor = [UIColor blackColor];
    _challengeTextField.placeholder = NSLocalizedString(@"VERIFICATION_CHALLENGE_DEFAULT_TEXT",
                                                        @"Text field placeholder for SMS verification code during registration");
    _challengeTextField.font = [UIFont ows_lightFontWithSize:21.f];
    _challengeTextField.textAlignment = NSTextAlignmentCenter;
    _challengeTextField.delegate    = self;
    [self.view addSubview:_challengeTextField];
    [_challengeTextField autoPinWidthToSuperviewWithMargin:ScaleFromIPhone5To7Plus(36, 36)];
    [_challengeTextField autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:_phoneNumberLabel
                          withOffset:ScaleFromIPhone5To7Plus(25, 25)];
    
    UIView *underscoreView = [UIView new];
    underscoreView.backgroundColor = [UIColor colorWithWhite:0.5 alpha:1.f];
    [self.view addSubview:underscoreView];
    [underscoreView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:_challengeTextField
                     withOffset:ScaleFromIPhone5To7Plus(3, 3)];
    [underscoreView autoPinWidthToSuperviewWithMargin:ScaleFromIPhone5To7Plus(36, 36)];
    [underscoreView autoSetDimension:ALDimensionHeight toSize:1.f];
    
    _challengeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _challengeButton.backgroundColor = signalBlueColor;
    [_challengeButton setTitle:NSLocalizedString(@"VERIFICATION_CHALLENGE_SUBMIT_CODE", @"button text during registration to submit your SMS verification code")
                     forState:UIControlStateNormal];
    [_challengeButton setTitleColor:[UIColor whiteColor]
                     forState:UIControlStateNormal];
    _challengeButton.titleLabel.font = [UIFont ows_mediumFontWithSize:14.f];
    [_challengeButton addTarget:self
                         action:@selector(verifyChallengeAction:)
               forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_challengeButton];
    [_challengeButton autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:underscoreView
                      withOffset:ScaleFromIPhone5To7Plus(15, 15)];
    [_challengeButton autoPinWidthToSuperviewWithMargin:ScaleFromIPhone5To7Plus(36, 36)];
    [_challengeButton autoSetDimension:ALDimensionHeight toSize:47.f];

    _submitCodeSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    [_challengeButton addSubview:_submitCodeSpinner];
    [_submitCodeSpinner autoSetDimension:ALDimensionWidth toSize:ScaleFromIPhone5To7Plus(20, 20)];
    [_submitCodeSpinner autoSetDimension:ALDimensionHeight toSize:ScaleFromIPhone5To7Plus(20, 20)];
    [_submitCodeSpinner autoVCenterInSuperview];
    [_submitCodeSpinner autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:ScaleFromIPhone5To7Plus(15, 15)];
    
    _sendCodeViaSMSAgainButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _sendCodeViaSMSAgainButton.backgroundColor = [UIColor whiteColor];
    [_sendCodeViaSMSAgainButton setTitle:NSLocalizedString(@"VERIFICATION_CHALLENGE_SUBMIT_AGAIN", @"button text during registration to request another SMS code be sent")
                               forState:UIControlStateNormal];
    [_sendCodeViaSMSAgainButton setTitleColor:signalBlueColor
                                    forState:UIControlStateNormal];
    _sendCodeViaSMSAgainButton.titleLabel.font = [UIFont ows_mediumFontWithSize:14.f];
    [_sendCodeViaSMSAgainButton addTarget:self
                                   action:@selector(sendCodeViaSMSAction:)
                         forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_sendCodeViaSMSAgainButton];
    [_sendCodeViaSMSAgainButton autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:_challengeButton
                                withOffset:ScaleFromIPhone5To7Plus(10, 10)];
    [_sendCodeViaSMSAgainButton autoPinWidthToSuperviewWithMargin:ScaleFromIPhone5To7Plus(36, 36)];
    [_sendCodeViaSMSAgainButton autoSetDimension:ALDimensionHeight toSize:35];
    
    _requestCodeAgainSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [_sendCodeViaSMSAgainButton addSubview:_requestCodeAgainSpinner];
    [_requestCodeAgainSpinner autoSetDimension:ALDimensionWidth toSize:ScaleFromIPhone5To7Plus(20, 20)];
    [_requestCodeAgainSpinner autoSetDimension:ALDimensionHeight toSize:ScaleFromIPhone5To7Plus(20, 20)];
    [_requestCodeAgainSpinner autoVCenterInSuperview];
    [_requestCodeAgainSpinner autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:ScaleFromIPhone5To7Plus(15, 15)];
    
    _sendCodeViaVoiceButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _sendCodeViaVoiceButton.backgroundColor = [UIColor whiteColor];
    [_sendCodeViaVoiceButton setTitle:NSLocalizedString(@"VERIFICATION_CHALLENGE_SEND_VIA_VOICE",
                                @"button text during registration to request phone number verification be done via phone call")
                            forState:UIControlStateNormal];
    [_sendCodeViaVoiceButton setTitleColor:signalBlueColor
                                    forState:UIControlStateNormal];
    _sendCodeViaVoiceButton.titleLabel.font = [UIFont ows_mediumFontWithSize:14.f];
    [_sendCodeViaVoiceButton addTarget:self
                                action:@selector(sendCodeViaVoiceAction:)
                      forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_sendCodeViaVoiceButton];
    [_sendCodeViaVoiceButton autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:_sendCodeViaSMSAgainButton
                                withOffset:ScaleFromIPhone5To7Plus(0, 0)];
    [_sendCodeViaVoiceButton autoPinWidthToSuperviewWithMargin:ScaleFromIPhone5To7Plus(36, 36)];
    [_sendCodeViaVoiceButton autoSetDimension:ALDimensionHeight toSize:35];
    
    _requestCallSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [_sendCodeViaVoiceButton addSubview:_requestCallSpinner];
    [_requestCallSpinner autoSetDimension:ALDimensionWidth toSize:ScaleFromIPhone5To7Plus(20, 20)];
    [_requestCallSpinner autoSetDimension:ALDimensionHeight toSize:ScaleFromIPhone5To7Plus(20, 20)];
    [_requestCallSpinner autoVCenterInSuperview];
    [_requestCallSpinner autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:ScaleFromIPhone5To7Plus(15, 15)];
}

- (void)updatePhoneNumberLabel {
    NSString *phoneNumber = [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:[TSAccountManager localNumber]];

    _phoneNumberLabel.text = [NSString stringWithFormat:NSLocalizedString(@"VERIFICATION_PHONE_NUMBER_FORMAT",
                                                                         @"Label indicating the phone number currently being verified."),
                             phoneNumber];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self enableServerActions:YES];
    [self updatePhoneNumberLabel];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_challengeTextField becomeFirstResponder];
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

- (void)verifyChallengeAction:(nullable id)sender
{
    [self startActivityIndicator];
    [self.accountManager registerWithVerificationCode:[self validationCodeFromTextField]]
        .then(^{
            DDLogInfo(@"%@ Successfully registered Signal account.", self.tag);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self stopActivityIndicator];
                [self performSegueWithIdentifier:kCompletedRegistrationSegue sender:nil];
            });
        })
        .catch(^(NSError *_Nonnull error) {
            DDLogError(@"%@ error verifying challenge: %@", self.tag, error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self stopActivityIndicator];
                [self presentAlertWithVerificationError:error];
            });
        });
}


- (void)presentAlertWithVerificationError:(NSError *)error
{
    UIAlertController *alertController = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"REGISTRATION_VERIFICATION_FAILED_TITLE", @"Alert view title")
                         message:error.localizedDescription
                  preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"DISMISS_BUTTON_TEXT", nil)
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction *action) {
                                                              [_challengeTextField becomeFirstResponder];
                                                          }];
    [alertController addAction:dismissAction];

    [self presentViewController:alertController animated:YES completion:nil];
}

- (NSString *)validationCodeFromTextField {
    return [self.challengeTextField.text stringByReplacingOccurrencesOfString:@"-" withString:@""];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(nullable id)sender
{
    DDLogInfo(@"%@ preparing for CompletedRegistrationSeque", self.tag);
    if ([segue.identifier isEqualToString:kCompletedRegistrationSegue]) {
        if (![segue.destinationViewController isKindOfClass:[SignalsNavigationController class]]) {
            DDLogError(@"%@ Unexpected destination view controller: %@", self.tag, segue.destinationViewController);
            return;
        }

        SignalsNavigationController *snc = (SignalsNavigationController *)segue.destinationViewController;

        AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
        appDelegate.window.rootViewController = snc;
        if (![snc.topViewController isKindOfClass:[SignalsViewController class]]) {
            DDLogError(@"%@ Unexpected top view controller: %@", self.tag, snc.topViewController);
            return;
        }

        DDLogDebug(@"%@ notifying signals view controller of new user.", self.tag);
        SignalsViewController *signalsViewController = (SignalsViewController *)snc.topViewController;
        signalsViewController.newlyRegisteredUser = YES;
    }
}

#pragma mark - Send codes again

- (void)sendCodeViaSMSAction:(id)sender {
    [self enableServerActions:NO];

    [_requestCodeAgainSpinner startAnimating];
    [TSAccountManager rerequestSMSWithSuccess:^{
        DDLogInfo(@"%@ Successfully requested SMS code", self.tag);
        [self enableServerActions:YES];
        [_requestCodeAgainSpinner stopAnimating];
    }
        failure:^(NSError *error) {
            DDLogError(@"%@ Failed to request SMS code with error: %@", self.tag, error);
            [self showRegistrationErrorMessage:error];
            [self enableServerActions:YES];
            [_requestCodeAgainSpinner stopAnimating];
        }];
}

- (void)sendCodeViaVoiceAction:(id)sender {
    [self enableServerActions:NO];

    [_requestCallSpinner startAnimating];
    [TSAccountManager rerequestVoiceWithSuccess:^{
        DDLogInfo(@"%@ Successfully requested voice code", self.tag);

        [self enableServerActions:YES];
        [_requestCallSpinner stopAnimating];
    }
        failure:^(NSError *error) {
            DDLogError(@"%@ Failed to request voice code with error: %@", self.tag, error);
            [self showRegistrationErrorMessage:error];
            [self enableServerActions:YES];
            [_requestCallSpinner stopAnimating];
        }];
}

- (void)showRegistrationErrorMessage:(NSError *)registrationError {
    UIAlertView *registrationErrorAV = [[UIAlertView alloc] initWithTitle:registrationError.localizedDescription
                                                                  message:registrationError.localizedRecoverySuggestion
                                                                 delegate:nil
                                                        cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                                        otherButtonTitles:nil, nil];

    [registrationErrorAV show];
}

- (void)enableServerActions:(BOOL)enabled {
    [_challengeButton setEnabled:enabled];
    [_sendCodeViaSMSAgainButton setEnabled:enabled];
    [_sendCodeViaVoiceButton setEnabled:enabled];
}

- (void)backButtonPressed:(id)sender {
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Keyboard notifications

- (void)initializeKeyboardHandlers {
    UITapGestureRecognizer *outsideTabRecognizer =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboardFromAppropriateSubView)];
    [self.view addGestureRecognizer:outsideTabRecognizer];
}

- (void)dismissKeyboardFromAppropriateSubView {
    [self.view endEditing:NO];
}

- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)string {
    if (range.location == 7) {
        return NO;
    }

    if (range.length == 0 &&
        ![[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[string characterAtIndex:0]]) {
        return NO;
    }

    if (range.length == 0 && range.location == 2) {
        textField.text = [NSString stringWithFormat:@"%@%@-", textField.text, string];
        return NO;
    }

    if (range.length == 1 && range.location == 3) {
        range.location--;
        range.length   = 2;
        textField.text = [textField.text stringByReplacingCharactersInRange:range withString:@""];
        return NO;
    }

    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self verifyChallengeAction:nil];
    [textField resignFirstResponder];
    return NO;
}

- (void)setVerificationCodeAndTryToVerify:(NSString *)verificationCode {
    self.challengeTextField.text = verificationCode;
    [self verifyChallengeAction:nil];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
