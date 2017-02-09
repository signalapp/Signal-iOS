//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "RegistrationViewController.h"

#import "CodeVerificationViewController.h"
#import "Environment.h"
#import "LocalizableText.h"
#import "PhoneNumber.h"
#import "PhoneNumberUtil.h"
#import "SignalKeyingStorage.h"
#import "TSAccountManager.h"
#import "Util.h"

static NSString *const kCodeSentSegue = @"codeSent";

@interface RegistrationViewController ()

@end

@implementation RegistrationViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
    _phoneNumberTextField.delegate = self;
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

#pragma mark - Locale

- (void)populateDefaultCountryNameAndCode {
    NSLocale *locale      = NSLocale.currentLocale;
    NSString *countryCode = [locale objectForKey:NSLocaleCountryCode];
    NSNumber *cc          = [[PhoneNumberUtil sharedUtil].nbPhoneNumberUtil getCountryCodeForRegion:countryCode];

    [_countryCodeButton setTitle:[NSString stringWithFormat:@"%@%@", COUNTRY_CODE_PREFIX, cc]
                        forState:UIControlStateNormal];
    [_countryNameButton setTitle:[PhoneNumberUtil countryNameFromCountryCode:countryCode]
                        forState:UIControlStateNormal];
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
    NSString *phoneNumber =
        [NSString stringWithFormat:@"%@%@", _countryCodeButton.titleLabel.text, _phoneNumberTextField.text];
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
                replacementString:(NSString *)string {
    NSString *textBeforeChange = textField.text;

    // backspacing should skip over formatting characters
    UITextPosition *posIfBackspace = [textField positionFromPosition:textField.beginningOfDocument
                                                              offset:(NSInteger)(range.location + range.length)];
    UITextRange *rangeIfBackspace = [textField textRangeFromPosition:posIfBackspace toPosition:posIfBackspace];
    bool isBackspace =
        string.length == 0 && range.length == 1 && [rangeIfBackspace isEqual:textField.selectedTextRange];
    if (isBackspace) {
        NSString *digits                       = textBeforeChange.digitsOnly;
        NSUInteger correspondingDeletePosition = [PhoneNumberUtil translateCursorPosition:range.location + range.length
                                                                                     from:textBeforeChange
                                                                                       to:digits
                                                                        stickingRightward:true];
        if (correspondingDeletePosition > 0) {
            textBeforeChange = digits;
            range            = NSMakeRange(correspondingDeletePosition - 1, 1);
        }
    }

    // make the proposed change
    NSString *textAfterChange            = [textBeforeChange withCharactersInRange:range replacedBy:string];
    NSUInteger cursorPositionAfterChange = range.location + string.length;

    // reformat the phone number, trying to keep the cursor beside the inserted or deleted digit
    bool isJustDeletion = string.length == 0;
    NSString *textAfterReformat =
        [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:textAfterChange.digitsOnly
                                                     withSpecifiedCountryCodeString:_countryCodeButton.titleLabel.text];
    NSUInteger cursorPositionAfterReformat = [PhoneNumberUtil translateCursorPosition:cursorPositionAfterChange
                                                                                 from:textAfterChange
                                                                                   to:textAfterReformat
                                                                    stickingRightward:isJustDeletion];
    textField.text = textAfterReformat;
    UITextPosition *pos =
        [textField positionFromPosition:textField.beginningOfDocument offset:(NSInteger)cursorPositionAfterReformat];
    [textField setSelectedTextRange:[textField textRangeFromPosition:pos toPosition:pos]];

    return NO; // inform our caller that we took care of performing the change
}

#pragma mark - Unwind segue

- (IBAction)unwindToChangeNumber:(UIStoryboardSegue *)sender {
}

- (IBAction)unwindToCountryCodeSelectionCancelled:(UIStoryboardSegue *)segue {
}

- (IBAction)unwindToCountryCodeWasSelected:(UIStoryboardSegue *)segue {
    CountryCodeViewController *vc = [segue sourceViewController];
    [_countryCodeButton setTitle:vc.callingCodeSelected forState:UIControlStateNormal];
    [_countryNameButton setTitle:vc.countryNameSelected forState:UIControlStateNormal];

    // Reformat phone number
    NSString *digits = _phoneNumberTextField.text.digitsOnly;
    NSString *reformattedNumber =
        [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:digits
                                                     withSpecifiedCountryCodeString:_countryCodeButton.titleLabel.text];
    _phoneNumberTextField.text = reformattedNumber;
    UITextPosition *pos        = _phoneNumberTextField.endOfDocument;
    [_phoneNumberTextField setSelectedTextRange:[_phoneNumberTextField textRangeFromPosition:pos toPosition:pos]];
}

#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([[segue identifier] isEqualToString:kCodeSentSegue]) {
    }
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
