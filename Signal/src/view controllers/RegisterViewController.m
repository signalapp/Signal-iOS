#import "RPServerRequestsManager.h"
#import "Environment.h"
#import "HTTPManager.h"
#import "LocalizableText.h"
#import "NBAsYouTypeFormatter.h"
#import "PhoneNumber.h"
#import "PhoneNumberDirectoryFilterManager.h"
#import "PhoneNumberUtil.h"
#import "PropertyListPreferences+Util.h"
#import "PushManager.h"
#import "RegisterViewController.h"
#import "RPServerRequestsManager.h"
#import "HTTPRequest+SignalUtil.h"
#import "SGNKeychainUtil.h"
#import "ThreadManager.h"
#import "Util.h"

#import <Pastelog.h>

#define REGISTER_VIEW_NUMBER 0
#define CHALLENGE_VIEW_NUMBER 1

#define COUNTRY_CODE_CHARACTER_MAX 3

#define SERVER_TIMEOUT_SECONDS 20
#define SMS_VERIFICATION_TIMEOUT_SECONDS 4*60
#define VOICE_VERIFICATION_COOLDOWN_SECONDS 4

#define IPHONE_BLUE [UIColor colorWithRed:22 green:173 blue:214 alpha:1]

@interface RegisterViewController ()

@property (strong, nonatomic) NSTimer* countdownTimer;
@property (strong, nonatomic) NSDate* timeoutDate;

@property (strong, nonatomic) TOCFutureSource* registered;
@property (strong, nonatomic) TOCFutureSource* futureChallengeAcceptedSource;
@property (strong, nonatomic) TOCCancelTokenSource* life;

@end

@implementation RegisterViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self localizeButtonText];
    
    DDLogInfo(@"Opened Registration View");
    
    [self populateDefaultCountryNameAndCode];
    
    self.scrollView.contentSize = self.containerView.bounds.size;
    
    BOOL isRegisteredAlready = Environment.isRegistered;
    self.registerCancelButton.hidden = !isRegisteredAlready;
    
    [self initializeKeyboardHandlers];
    [self setPlaceholderTextColor:UIColor.lightGrayColor];
}

- (instancetype)init {
    if (self = [super init]) {
        self.life = [[TOCCancelTokenSource alloc] init];
        self.registered = [TOCFutureSource futureSourceUntil:self.life.token];
    }
    
    return self;
}


- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

- (void)setPlaceholderTextColor:(UIColor*)color {
    NSAttributedString* placeholder = self.phoneNumberTextField.attributedPlaceholder;
    if (placeholder.length) {
        NSDictionary* attributes = [placeholder attributesAtIndex:0 effectiveRange:NULL];
        
        NSMutableDictionary* newAttributes = [[NSMutableDictionary alloc] initWithDictionary:attributes];
        newAttributes[NSForegroundColorAttributeName] = color;
        
        NSString* placeholderString = [placeholder string];
        self.phoneNumberTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholderString
                                                                                          attributes:newAttributes];
    }
}

- (void)localizeButtonText {
    [self.registerCancelButton      setTitle:TXT_CANCEL_TITLE            forState:UIControlStateNormal];
    [self.continueToWhisperButton   setTitle:CONTINUE_TO_WHISPER_TITLE   forState:UIControlStateNormal];
    [self.registerButton            setTitle:REGISTER_BUTTON_TITLE       forState:UIControlStateNormal];
    [self.challengeButton           setTitle:CHALLENGE_CODE_BUTTON_TITLE forState:UIControlStateNormal];
}

- (IBAction)registerCancelButtonTapped {
    [self dismissView];
}

- (void) dismissView {
    [self stopVoiceVerificationCountdownTimer];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)populateDefaultCountryNameAndCode {
    NSLocale* locale = NSLocale.currentLocale;
    NSString* countryCode = [locale objectForKey:NSLocaleCountryCode];
    NSNumber* cc = [NBPhoneNumberUtil.sharedInstance getCountryCodeForRegion:countryCode];
    
    self.countryCodeLabel.text = [NSString stringWithFormat:@"%@%@",COUNTRY_CODE_PREFIX, cc];
    self.countryNameLabel.text = [PhoneNumberUtil countryNameFromCountryCode:countryCode];
}

- (IBAction)changeNumberTapped {
    [self showViewNumber:REGISTER_VIEW_NUMBER];
}

- (IBAction)changeCountryCodeTapped {
    CountryCodeViewController* countryCodeController = [[CountryCodeViewController alloc] init];
    countryCodeController.delegate = self;
    [self presentViewController:countryCodeController animated:YES completion:nil];
}

- (void)registerPhoneNumberTapped {
    NSString* phoneNumber = [NSString stringWithFormat:@"%@%@", self.countryCodeLabel.text, self.phoneNumberTextField.text];
    PhoneNumber* localNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumber];
    if (localNumber == nil) return;
    
    [self.phoneNumberTextField resignFirstResponder];
    
    [self.registerActivityIndicator startAnimating];
    self.registerButton.enabled = NO;
    
    [SGNKeychainUtil setLocalNumberTo:localNumber];
    
    [RPServerRequestsManager.sharedInstance performRequest:[RPAPICall requestVerificationCode]
                                                     success:^(NSURLSessionDataTask *task, id responseObject) {
        [self showViewNumber:CHALLENGE_VIEW_NUMBER];
        [self.challengeNumberLabel setText:phoneNumber.description];
        [self.registerCancelButton removeFromSuperview];
        [self startVoiceVerificationCountdownTimer];
    } failure:^(NSURLSessionDataTask* task, NSError* error) {
        [self.registerActivityIndicator stopAnimating];
        self.registerButton.enabled = YES;
        
        DDLogError(@"Registration failed with information %@", error.description);
        
#warning Deprecated method
        UIAlertView* registrationErrorAV = [[UIAlertView alloc] initWithTitle:REGISTER_ERROR_ALERT_VIEW_TITLE
                                                                      message:REGISTER_ERROR_ALERT_VIEW_BODY
                                                                     delegate:nil
                                                            cancelButtonTitle:REGISTER_ERROR_ALERT_VIEW_DISMISS
                                                            otherButtonTitles:nil, nil];
        
        [registrationErrorAV show];
    }];
}

- (void)dismissTapped {
    [self dismissView];
}

- (void)verifyChallengeTapped {
    [self.challengeTextField resignFirstResponder];
    self.challengeButton.enabled = NO;
    [self.challengeActivityIndicator startAnimating];
    
    [RPServerRequestsManager.sharedInstance performRequest:[RPAPICall verifyVerificationCode:self.challengeTextField.text]
                                                     success:^(NSURLSessionDataTask *task, id responseObject) {
        
        [PushManager.sharedManager registrationWithSuccess:^{
            [self.futureChallengeAcceptedSource trySetResult:@YES];
            [Environment setRegistered:YES];
            [self.registered trySetResult:@YES];
            [Environment.getCurrent.phoneDirectoryManager forceUpdate];
            [self dismissView];
        } failure:^{
            self.challengeButton.enabled = YES;
            [self.challengeActivityIndicator stopAnimating];
        }];
        
    } failure:^(NSURLSessionDataTask* task, NSError* error) {
        NSString* alertTitle = NSLocalizedString(@"REGISTRATION_ERROR", @"");
        
        NSHTTPURLResponse* badResponse = (NSHTTPURLResponse*)task.response;
        if (badResponse.statusCode == 401) {
            SignalAlertView(alertTitle, REGISTER_CHALLENGE_ALERT_VIEW_BODY);
        } else if (badResponse.statusCode == 413) {
            SignalAlertView(alertTitle, NSLocalizedString(@"REGISTER_RATE_LIMITING_BODY", @""));
        } else {
            NSString* alertBodyString = [NSString stringWithFormat:@"%@ %lu", NSLocalizedString(@"SERVER_CODE", @""),(unsigned long)badResponse.statusCode];
            SignalAlertView (alertTitle, alertBodyString);
        }
        
        self.challengeButton.enabled = YES;
        [self.challengeActivityIndicator stopAnimating];
    }];
}

- (void)showViewNumber:(NSInteger)viewNumber {
    
    if (viewNumber == REGISTER_VIEW_NUMBER) {
        [self.registerActivityIndicator stopAnimating];
        self.registerButton.enabled = YES;
    }
    
    [self stopVoiceVerificationCountdownTimer];
    
    [self.scrollView setContentOffset:CGPointMake(self.scrollView.frame.size.width*viewNumber, 0) animated:YES];
}

- (void)presentInvalidCountryCodeError {
#warning Deprecated method
    UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:REGISTER_CC_ERR_ALERT_VIEW_TITLE
                                                        message:REGISTER_CC_ERR_ALERT_VIEW_MESSAGE
                                                       delegate:nil
                                              cancelButtonTitle:REGISTER_CC_ERR_ALERT_VIEW_DISMISS
                                              otherButtonTitles:nil];
    [alertView show];
}

- (void)startVoiceVerificationCountdownTimer {
    [self.initiateVoiceVerificationButton.titleLabel setTextAlignment:NSTextAlignmentCenter];
    self.initiateVoiceVerificationButton.hidden = NO;
    
    NSTimeInterval smsTimeoutTimeInterval = SMS_VERIFICATION_TIMEOUT_SECONDS;
    
    NSDate* now = [[NSDate alloc] init];
    self.timeoutDate = [[NSDate alloc] initWithTimeInterval:smsTimeoutTimeInterval sinceDate:now];
    
    self.countdownTimer = [NSTimer scheduledTimerWithTimeInterval:1
                                                           target:self
                                                         selector:@selector(countdowntimerFired)
                                                         userInfo:nil repeats:YES];
}

- (void)stopVoiceVerificationCountdownTimer {
    [self.countdownTimer invalidate];
}

- (void)countdowntimerFired {
    NSDate* now = [[NSDate alloc] init];
    
    unsigned int unitFlags = NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit;
    NSDateComponents* conversionInfo = [[NSCalendar currentCalendar] components:unitFlags
                                                                       fromDate:now
                                                                         toDate:self.timeoutDate
                                                                        options:0];
    NSString* timeLeft = [NSString stringWithFormat:@"%ld:%02ld",(long)[conversionInfo minute],(long)[conversionInfo second]];
    
    [self.voiceChallengeTextLabel setText:timeLeft];
    
    if (0 <= [now  compare:self.timeoutDate]) {
        [self initiateVoiceVerification];
    }
    
}

- (void)initiateVoiceVerification {
    [self stopVoiceVerificationCountdownTimer];
    [self.voiceChallengeTextLabel setText:NSLocalizedString(@"REGISTER_CALL_CALLING", @"")];
    
    [RPServerRequestsManager.sharedInstance performRequest:[RPAPICall requestVerificationCodeWithVoice]
                                                     success:^(NSURLSessionDataTask *task, id responseObject) {
        
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, VOICE_VERIFICATION_COOLDOWN_SECONDS * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void) {
            [self.voiceChallengeTextLabel setText:NSLocalizedString(@"REGISTER_CALL_RECALL", @"")];
        });
        
    } failure:^(NSURLSessionDataTask* task, NSError* error) {
        [self.voiceChallengeTextLabel setText:error.description];
    }];
}

- (IBAction)initiateVoiceVerificationButtonHandler {
    [self initiateVoiceVerification];
}

#pragma mark - Keyboard notifications

- (void)initializeKeyboardHandlers {
    UITapGestureRecognizer *outsideTabRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboardFromAppropriateSubView)];
    [self.view addGestureRecognizer:outsideTabRecognizer];
    
    [self observeKeyboardNotifications];
    
}

- (void)dismissKeyboardFromAppropriateSubView {
    [self.view endEditing:NO];
}

- (void)observeKeyboardNotifications {
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(keyboardWillShow:)
                                               name:UIKeyboardWillShowNotification
                                             object:nil];
    
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(keyboardWillHide:)
                                               name:UIKeyboardWillHideNotification
                                             object:nil];
}

- (void)keyboardWillShow:(NSNotification*)notification {
    double duration = [[notification userInfo][UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;;
        self.scrollView.frame = CGRectMake(CGRectGetMinX(self.scrollView.frame),
                                           CGRectGetMinY(self.scrollView.frame)-keyboardSize.height,
                                           CGRectGetWidth(self.scrollView.frame),
                                           CGRectGetHeight(self.scrollView.frame));
    }];
}

- (void)keyboardWillHide:(NSNotification*)notification {
    double duration = [[notification userInfo][UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        self.scrollView.frame = CGRectMake(CGRectGetMinX(self.scrollView.frame),
                                           CGRectGetMinY(self.view.frame),
                                           CGRectGetWidth(self.scrollView.frame),
                                           CGRectGetHeight(self.scrollView.frame));
    }];
}

#pragma mark - CountryCodeViewControllerDelegate

- (void)countryCodeViewController:(CountryCodeViewController*)vc
             didSelectCountryCode:(NSString*)code
                       forCountry:(NSString*)country {
    self.countryCodeLabel.text = code;
    self.countryNameLabel.text = country;
    
    // Reformat phone number
    NSString* digits = self.phoneNumberTextField.text.digitsOnly;
    NSString* reformattedNumber = [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:digits
                                                                               withSpecifiedCountryCodeString:self.countryCodeLabel.text];
    self.phoneNumberTextField.text = reformattedNumber;
    UITextPosition* pos = self.phoneNumberTextField.endOfDocument;
    [self.phoneNumberTextField setSelectedTextRange:[self.phoneNumberTextField textRangeFromPosition:pos toPosition:pos]];
    
    // Done choosing country
    [vc dismissViewControllerAnimated:YES completion:nil];
}

- (void)countryCodeViewControllerDidCancel:(CountryCodeViewController*)vc {
    [vc dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField*)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString*)string {
    NSString* textBeforeChange = textField.text;
    
    // backspacing should skip over formatting characters
    UITextPosition* posIfBackspace = [textField positionFromPosition:textField.beginningOfDocument
                                                              offset:(NSInteger)(range.location + range.length)];
    UITextRange* rangeIfBackspace = [textField textRangeFromPosition:posIfBackspace toPosition:posIfBackspace];
    bool isBackspace = string.length == 0 && range.length == 1 && [rangeIfBackspace isEqual:textField.selectedTextRange];
    if (isBackspace) {
        NSString* digits = textBeforeChange.digitsOnly;
        NSUInteger correspondingDeletePosition = [PhoneNumberUtil translateCursorPosition:range.location + range.length
                                                                                     from:textBeforeChange
                                                                                       to:digits
                                                                        stickingRightward:true];
        if (correspondingDeletePosition > 0) {
            textBeforeChange = digits;
            range = NSMakeRange(correspondingDeletePosition - 1, 1);
        }
    }
    
    // make the proposed change
    NSString* textAfterChange = [textBeforeChange withCharactersInRange:range replacedBy:string];
    NSUInteger cursorPositionAfterChange = range.location + string.length;
    
    // reformat the phone number, trying to keep the cursor beside the inserted or deleted digit
    bool isJustDeletion = string.length == 0;
    NSString* textAfterReformat = [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:textAfterChange.digitsOnly
                                                                               withSpecifiedCountryCodeString:self.countryCodeLabel.text];
    NSUInteger cursorPositionAfterReformat = [PhoneNumberUtil translateCursorPosition:cursorPositionAfterChange
                                                                                 from:textAfterChange
                                                                                   to:textAfterReformat
                                                                    stickingRightward:isJustDeletion];
    textField.text = textAfterReformat;
    UITextPosition* pos = [textField positionFromPosition:textField.beginningOfDocument
                                                   offset:(NSInteger)cursorPositionAfterReformat];
    [textField setSelectedTextRange:[textField textRangeFromPosition:pos toPosition:pos]];
    
    return NO; // inform our caller that we took care of performing the change
}

@end
