//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "RegistrationViewController.h"
#import "CodeVerificationViewController.h"
#import "Environment.h"
#import "PhoneNumber.h"
#import "PhoneNumberUtil.h"
#import "SignalKeyingStorage.h"
#import "TSAccountManager.h"
#import "UIView+OWS.h"
#import "Util.h"
#import "ViewControllerUtils.h"

static NSString *const kCodeSentSegue = @"codeSent";

@interface RegistrationViewController ()

@property (nonatomic) NSString *lastCallingCode;
@property (nonatomic) NSString *lastCountryCode;

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
    [_countryNameButton setTitle:NSLocalizedString(@"REGISTRATION_DEFAULT_COUNTRY_NAME", @"")
                        forState:UIControlStateNormal];
    _phoneNumberTextField.placeholder = NSLocalizedString(@"REGISTRATION_ENTERNUMBER_DEFAULT_TEXT", @"");
    [_phoneNumberButton setTitle:NSLocalizedString(@"REGISTRATION_PHONENUMBER_BUTTON", @"")
                        forState:UIControlStateNormal];
    [_phoneNumberButton.titleLabel setAdjustsFontSizeToFitWidth:YES];
    [_sendCodeButton setTitle:NSLocalizedString(@"REGISTRATION_VERIFY_DEVICE", @"") forState:UIControlStateNormal];
    [_existingUserButton setTitle:NSLocalizedString(@"ALREADY_HAVE_ACCOUNT_BUTTON", @"registration button text")
                         forState:UIControlStateNormal];
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

    _lastCallingCode = callingCode;
    _lastCountryCode = countryCode;

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

    NSString *alertTitleFormat = NSLocalizedString(@"EXISTING_USER_REGISTRATION_ALERT_TITLE",
        @"during registration, embeds {{device type}}, e.g. \"iPhone\" or \"iPad\"");
    NSString *alertTitle = [NSString stringWithFormat:alertTitleFormat, [UIDevice currentDevice].localizedModel];
    NSString *alertBody = NSLocalizedString(@"EXISTING_USER_REGISTRATION_ALERT_BODY", @"during registration");
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:alertTitle
                                                                             message:alertBody
                                                                      preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleCancel handler:nil];
    [alertController addAction:cancelAction];

    [self presentViewController:alertController animated:YES completion:nil];
}

- (IBAction)sendCodeAction:(id)sender {
    NSString *phoneNumber = [NSString stringWithFormat:@"%@%@", _lastCallingCode, _phoneNumberTextField.text];
    PhoneNumber *localNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumber];

    [_sendCodeButton setEnabled:NO];
    [_spinnerView startAnimating];
    [_phoneNumberTextField resignFirstResponder];

    [TSAccountManager registerWithPhoneNumber:localNumber.toE164
        success:^{
          [self performSegueWithIdentifier:@"codeSent" sender:self];
          [_spinnerView stopAnimating];
        }
        failure:^(NSError *error) {
          if (error.code == 400) {
              SignalAlertView(NSLocalizedString(@"REGISTRATION_ERROR", nil),
                              NSLocalizedString(@"REGISTRATION_NON_VALID_NUMBER", ));
          } else {
              SignalAlertView(error.localizedDescription, error.localizedRecoverySuggestion);
          }

          [_sendCodeButton setEnabled:YES];
          [_spinnerView stopAnimating];
        }
        smsVerification:YES];
}

- (IBAction)changeCountryCodeTapped {
    CountryCodeViewController *countryCodeController = [CountryCodeViewController new];
    [self presentViewController:countryCodeController animated:YES completion:[UIUtil modalCompletionBlock]];
}

- (void)presentInvalidCountryCodeError {
    UIAlertView *alertView =
        [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"REGISTER_CC_ERR_ALERT_VIEW_TITLE", @"")
                                   message:NSLocalizedString(@"REGISTER_CC_ERR_ALERT_VIEW_MESSAGE", @"")
                                  delegate:nil
                         cancelButtonTitle:NSLocalizedString(@"DISMISS_BUTTON_TEXT",
                                               @"Generic short text for button to dismiss a dialog")
                         otherButtonTitles:nil];
    [alertView show];
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
                                  countryCode:_lastCountryCode];

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

- (IBAction)unwindToCountryCodeSelectionCancelled:(UIStoryboardSegue *)segue {
}

- (IBAction)unwindToCountryCodeWasSelected:(UIStoryboardSegue *)segue {
    CountryCodeViewController *vc = [segue sourceViewController];
    [self updateCountryWithName:vc.countryNameSelected
                    callingCode:vc.callingCodeSelected
                    countryCode:vc.countryCodeSelected];

    // Reformat phone number
    NSString *digits = _phoneNumberTextField.text.digitsOnly;
    NSString *reformattedNumber =
        [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:digits
                                                     withSpecifiedCountryCodeString:_countryCodeButton.titleLabel.text];
    _phoneNumberTextField.text = reformattedNumber;
    UITextPosition *pos        = _phoneNumberTextField.endOfDocument;
    [_phoneNumberTextField setSelectedTextRange:[_phoneNumberTextField textRangeFromPosition:pos toPosition:pos]];
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
