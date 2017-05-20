//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "RegistrationViewController.h"
#import "CodeVerificationViewController.h"
#import "Environment.h"
#import "PhoneNumber.h"
#import "PhoneNumberUtil.h"
#import "Signal-Swift.h"
#import "SignalKeyingStorage.h"
#import "TSAccountManager.h"
#import "UIView+OWS.h"
#import "Util.h"
#import "ViewControllerUtils.h"

static NSString *const kCodeSentSegue = @"codeSent";

@interface RegistrationViewController () <CountryCodeViewControllerDelegate>

@property (nonatomic) NSString *callingCode;

@end

#pragma mark -

@implementation RegistrationViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
    _phoneNumberTextField.delegate = self;
    _phoneNumberTextField.keyboardType = UIKeyboardTypeNumberPad;
    [self populateDefaultCountryNameAndCode];
    [[Environment getCurrent] setSignUpFlowNavigationController:self.navigationController];

    _titleLabel.text = NSLocalizedString(@"REGISTRATION_TITLE_LABEL", @"");
    [_countryNameButton
        setTitle:NSLocalizedString(@"REGISTRATION_DEFAULT_COUNTRY_NAME", @"Label for the country code field")
        forState:UIControlStateNormal];
    _phoneNumberTextField.placeholder = NSLocalizedString(
        @"REGISTRATION_ENTERNUMBER_DEFAULT_TEXT", @"Placeholder text for the phone number textfield");
    [_phoneNumberButton
        setTitle:NSLocalizedString(@"REGISTRATION_PHONENUMBER_BUTTON", @"Label for the phone number textfield")
        forState:UIControlStateNormal];
    [_phoneNumberButton.titleLabel setAdjustsFontSizeToFitWidth:YES];
    [_sendCodeButton setTitle:NSLocalizedString(@"REGISTRATION_VERIFY_DEVICE", @"") forState:UIControlStateNormal];
    [_existingUserButton setTitle:NSLocalizedString(@"ALREADY_HAVE_ACCOUNT_BUTTON", @"registration button text")
                         forState:UIControlStateNormal];

    [self.countryNameButton addTarget:self
                               action:@selector(changeCountryCodeTapped)
                     forControlEvents:UIControlEventTouchUpInside];
    [self.countryCodeButton addTarget:self
                               action:@selector(changeCountryCodeTapped)
                     forControlEvents:UIControlEventTouchUpInside];
    [self.countryCodeRow
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                     action:@selector(countryCodeRowWasTapped:)]];
}

- (void)viewWillAppear:(BOOL)animated {
    [self adjustScreenSizes];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [_sendCodeButton setEnabled:YES];
    [_spinnerView stopAnimating];
    [_phoneNumberTextField becomeFirstResponder];
}

#pragma mark - Country

- (void)populateDefaultCountryNameAndCode {
    NSLocale *locale      = NSLocale.currentLocale;
    NSString *countryCode = [locale objectForKey:NSLocaleCountryCode];
    NSNumber *callingCode = [[PhoneNumberUtil sharedUtil].nbPhoneNumberUtil getCountryCodeForRegion:countryCode];
    NSString *countryName = [PhoneNumberUtil countryNameFromCountryCode:countryCode];
    [self updateCountryWithName:countryName
                    callingCode:[NSString stringWithFormat:@"%@%@",
                                 COUNTRY_CODE_PREFIX,
                                 callingCode]
                    countryCode:countryCode];
}

- (void)updateCountryWithName:(NSString *)countryName
                  callingCode:(NSString *)callingCode
                  countryCode:(NSString *)countryCode {

    _callingCode = callingCode;

    NSString *title = [NSString stringWithFormat:@"%@ (%@)",
                       callingCode,
                       countryCode.uppercaseString];
    [_countryCodeButton setTitle:title
                        forState:UIControlStateNormal];
    
    // In the absence of a rewrite to a programmatic layout,
    // re-add the country code and name views in order to
    // remove any layout constraints that apply to them.
    UIView *superview = _countryCodeButton.superview;
    [_countryNameButton removeFromSuperview];
    [_countryCodeButton removeFromSuperview];
    [_countryNameButton removeConstraints:_countryNameButton.constraints];
    [_countryCodeButton removeConstraints:_countryCodeButton.constraints];

    [superview addSubview:_countryNameButton];
    [superview addSubview:_countryCodeButton];
    [_countryNameButton autoVCenterInSuperview];
    [_countryCodeButton autoVCenterInSuperview];
    [_countryNameButton autoSetDimension:ALDimensionHeight toSize:26];
    [_countryCodeButton autoSetDimension:ALDimensionHeight toSize:26];
    [_countryNameButton autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:20];
    [_countryCodeButton autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:16];
    [_countryNameButton autoSetDimension:ALDimensionWidth toSize:150];
    [_countryCodeButton autoSetDimension:ALDimensionWidth toSize:150];
    _countryNameButton.translatesAutoresizingMaskIntoConstraints = NO;
    _countryCodeButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    [superview layoutSubviews];
}

#pragma mark - Actions

- (IBAction)didTapExistingUserButton:(id)sender
{
    DDLogInfo(@"called %s", __PRETTY_FUNCTION__);

    [OWSAlerts
        showAlertWithTitle:
            [NSString stringWithFormat:NSLocalizedString(@"EXISTING_USER_REGISTRATION_ALERT_TITLE",
                                           @"during registration, embeds {{device type}}, e.g. \"iPhone\" or \"iPad\""),
                      [UIDevice currentDevice].localizedModel]
                   message:NSLocalizedString(@"EXISTING_USER_REGISTRATION_ALERT_BODY", @"during registration")];
}

- (IBAction)sendCodeAction:(id)sender {
    NSString *phoneNumberText =
        [_phoneNumberTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (phoneNumberText.length < 1) {
        [OWSAlerts
            showAlertWithTitle:NSLocalizedString(@"REGISTRATION_VIEW_NO_PHONE_NUMBER_ALERT_TITLE",
                                   @"Title of alert indicating that users needs to enter a phone number to register.")
                       message:
                           NSLocalizedString(@"REGISTRATION_VIEW_NO_PHONE_NUMBER_ALERT_MESSAGE",
                               @"Message of alert indicating that users needs to enter a phone number to register.")];
        return;
    }
    NSString *phoneNumber = [NSString stringWithFormat:@"%@%@", _callingCode, phoneNumberText];
    PhoneNumber *localNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumber];
    NSString *parsedPhoneNumber = localNumber.toE164;
    if (parsedPhoneNumber.length < 1) {
        [OWSAlerts showAlertWithTitle:
                       NSLocalizedString(@"REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_TITLE",
                           @"Title of alert indicating that users needs to enter a valid phone number to register.")
                              message:NSLocalizedString(@"REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_MESSAGE",
                                          @"Message of alert indicating that users needs to enter a valid phone number "
                                          @"to register.")];
        return;
    }

    [_sendCodeButton setEnabled:NO];
    [_spinnerView startAnimating];
    [_phoneNumberTextField resignFirstResponder];

    [TSAccountManager registerWithPhoneNumber:parsedPhoneNumber
        success:^{
            [self performSegueWithIdentifier:@"codeSent" sender:self];
            [_spinnerView stopAnimating];
        }
        failure:^(NSError *error) {
            if (error.code == 400) {
                [OWSAlerts showAlertWithTitle:NSLocalizedString(@"REGISTRATION_ERROR", nil)
                                      message:NSLocalizedString(@"REGISTRATION_NON_VALID_NUMBER", nil)];
            } else {
                [OWSAlerts showAlertWithTitle:error.localizedDescription message:error.localizedRecoverySuggestion];
            }

            [_sendCodeButton setEnabled:YES];
            [_spinnerView stopAnimating];
        }
        smsVerification:YES];
}

- (void)countryCodeRowWasTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self changeCountryCodeTapped];
    }
}

- (void)changeCountryCodeTapped
{
    CountryCodeViewController *countryCodeController = [[UIStoryboard storyboardWithName:@"Registration" bundle:NULL]
        instantiateViewControllerWithIdentifier:@"CountryCodeViewController"];
    countryCodeController.delegate = self;
    UINavigationController *navigationController =
        [[UINavigationController alloc] initWithRootViewController:countryCodeController];
    [self presentViewController:navigationController animated:YES completion:[UIUtil modalCompletionBlock]];
}

- (void)presentInvalidCountryCodeError {
    [OWSAlerts showAlertWithTitle:NSLocalizedString(@"REGISTER_CC_ERR_ALERT_VIEW_TITLE", @"")
                          message:NSLocalizedString(@"REGISTER_CC_ERR_ALERT_VIEW_MESSAGE", @"")
                      buttonTitle:NSLocalizedString(
                                      @"DISMISS_BUTTON_TEXT", @"Generic short text for button to dismiss a dialog")];
}

#pragma mark - CountryCodeViewControllerDelegate

- (void)countryCodeViewController:(CountryCodeViewController *)vc
             didSelectCountryCode:(NSString *)countryCode
                      countryName:(NSString *)countryName
                      callingCode:(NSString *)callingCode
{

    [self updateCountryWithName:countryName callingCode:callingCode countryCode:countryCode];

    // Trigger the formatting logic with a no-op edit.
    [self textField:self.phoneNumberTextField shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:@""];
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

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText {

    [ViewControllerUtils phoneNumberTextField:textField
                shouldChangeCharactersInRange:range
                            replacementString:insertionText
                                  countryCode:_callingCode];

    return NO; // inform our caller that we took care of performing the change
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendCodeAction:nil];
    [textField resignFirstResponder];
    return NO;
}

#pragma mark - Unwind segue

- (IBAction)unwindToChangeNumber:(UIStoryboardSegue *)sender {
}

#pragma mark iPhone 5s or shorter

- (void)adjustScreenSizes
{
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;

    if (screenHeight < 568) { // iphone 4s
        self.signalLogo.hidden = YES;
        _headerHeightConstraint.constant = 20;
    } else if (screenHeight < 667) { // iphone 5
        self.signalLogo.hidden = YES;
        _headerHeightConstraint.constant = 120;
    }
}

@end
