#import "Environment.h"
#import "HttpManager.h"
#import "KeyChainStorage.h"
#import "LocalizableText.h"
#import "NBAsYouTypeFormatter.h"
#import "PhoneNumber.h"
#import "PhoneNumberDirectoryFilterManager.h"
#import "PhoneNumberUtil.h"
#import "PreferencesUtil.h"
#import "RegisterViewController.h"
#import "SignalUtil.h"
#import "ThreadManager.h"
#import "Util.h"

#define REGISTER_VIEW_NUMBER 0
#define CHALLENGE_VIEW_NUMBER 1

#define COUNTRY_CODE_CHARACTER_MAX 3

#define SERVER_TIMEOUT_SECONDS 20
#define SMS_VERIFICATION_TIMEOUT_SECONDS 4*60
#define VOICE_VERIFICATION_COOLDOWN_SECONDS 4

#define IPHONE_BLUE [UIColor colorWithRed:22 green:173 blue:214 alpha:1]

@interface RegisterViewController () {
    NSMutableString *_enteredPhoneNumber;
    NSTimer* countdownTimer;
    NSDate *timeoutDate;
}

@end

@implementation RegisterViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self populateDefaultCountryNameAndCode];

    [futureApnId catchDo:^(id error) {
        // todo: remove this; just here for testing purposes to catch apn not being set
        _registerErrorLabel.text = [error description];
    }];
    
    _scrollView.contentSize = _containerView.bounds.size;

    BOOL isRegisteredAlready = [[Environment preferences] getIsRegistered];
    _registerCancelButton.hidden = !isRegisteredAlready;

    [self initializeKeyboardHandlers];
    [self setPlaceholderTextColor:[UIColor lightGrayColor]];
    _enteredPhoneNumber = [NSMutableString string];
}

+ (RegisterViewController*)registerViewControllerForApn:(Future *)apnId {
    require(apnId != nil);

    RegisterViewController *viewController = [RegisterViewController new];
    viewController->futureApnId = apnId;
    viewController->registered = [FutureSource new];
    viewController->life = [CancelTokenSource cancelTokenSource];
    [[viewController->life getToken] whenCancelledTryCancel:viewController->registered];

    return viewController;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

- (void)setPlaceholderTextColor:(UIColor *)color {
    NSAttributedString *placeholder = _phoneNumberTextField.attributedPlaceholder;
    if ([placeholder length]) {
        NSDictionary * attributes = [placeholder attributesAtIndex:0
                                                    effectiveRange:NULL];
        
        NSMutableDictionary *newAttributes = [[NSMutableDictionary alloc] initWithDictionary:attributes];
        [newAttributes setObject:color forKey:NSForegroundColorAttributeName];
        
        NSString *placeholderString = [placeholder string];
        _phoneNumberTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholderString
                                                                                      attributes:newAttributes];
    }
}

- (void)localizeButtonText {
    [_registerCancelButton      setTitle:TXT_CANCEL_TITLE forState:UIControlStateNormal];
    [_continueToWhisperButton   setTitle:CONTINUE_TO_WHISPER_TITLE forState:UIControlStateNormal];
    [_registerButton            setTitle:REGISTER_BUTTON_TITLE forState:UIControlStateNormal];
    [_challengeButton           setTitle:CHALLENGE_CODE_BUTTON_TITLE forState:UIControlStateNormal];
}

- (IBAction)registerCancelButtonTapped {
    [self dismissView];
}

- (void) dismissView {
    [self stopVoiceVerificationCountdownTimer];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)populateDefaultCountryNameAndCode {
    NSLocale *locale = [NSLocale currentLocale];
    NSString *countryCode = [locale objectForKey:NSLocaleCountryCode];
    NSNumber *cc = [[NBPhoneNumberUtil sharedInstance] getCountryCodeForRegion:countryCode];
    
    _countryCodeLabel.text = [NSString stringWithFormat:@"%@%@",COUNTRY_CODE_PREFIX, cc];
    _countryNameLabel.text = [PhoneNumberUtil countryNameFromCountryCode:countryCode];
}

- (IBAction)changeNumberTapped {
    [self showViewNumber:REGISTER_VIEW_NUMBER];
}

- (IBAction)changeCountryCodeTapped {
    CountryCodeViewController *countryCodeController = [CountryCodeViewController new];
    countryCodeController.delegate = self;
    [self presentViewController:countryCodeController animated:YES completion:nil];
}

-(Future*) asyncRegister:(PhoneNumber*)phoneNumber untilCancelled:(id<CancelToken>)cancelToken {
    // @todo: should we force regenerating of all keys?
    // @todo: clear current registered status before making a new one, to avoid splinching issues?
    [KeyChainStorage setLocalNumberTo:phoneNumber];

    CancellableOperationStarter regStarter = ^Future *(id<CancelToken> internalUntilCancelledToken) {
        HttpRequest *registerRequest = [HttpRequest httpRequestToStartRegistrationOfPhoneNumber];
       
        return [HttpManager asyncOkResponseFromMasterServer:registerRequest
                                            unlessCancelled:internalUntilCancelledToken
                                            andErrorHandler:[Environment errorNoter]];
    };
    Future *futurePhoneRegistrationStarted = [AsyncUtil raceCancellableOperation:regStarter
                                                                  againstTimeout:30.0
                                                                  untilCancelled:cancelToken];

    Future *futurePhoneRegistrationVerified = [futurePhoneRegistrationStarted then:^(id _) {
        [self showViewNumber:CHALLENGE_VIEW_NUMBER];
        [[Environment preferences] setIsRegistered:NO];
        [self.challengeNumberLabel setText:[phoneNumber description]];
        [_registerCancelButton removeFromSuperview];
        [self startVoiceVerificationCountdownTimer];
        self->futureChallengeAcceptedSource = [FutureSource new];
        return futureChallengeAcceptedSource;
    }];

    Future *futureApnToRegister = [futurePhoneRegistrationVerified then:^(HttpResponse* okResponse) {
        // @todo: keep handling code for simulator?
        return [futureApnId catch:^id(id error) {
            return nil;
        }];
    }];

    return [futureApnToRegister then:^Future*(NSData* deviceToken) {
        // @todo: distinguish between simulator no-apn error and other no-apn errors
        if (deviceToken == nil) return futureApnToRegister;
        
        HttpRequest* request = [HttpRequest httpRequestToRegisterForApnSignalingWithDeviceToken:deviceToken];
        return [HttpManager asyncOkResponseFromMasterServer:request
                                            unlessCancelled:cancelToken
                                            andErrorHandler:[Environment errorNoter]];
    }];    
}

- (void)registerPhoneNumberTapped {
    NSString *phoneNumber = [NSString stringWithFormat:@"%@%@", _countryCodeLabel.text, _phoneNumberTextField.text];
    PhoneNumber* localNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumber];
    if(localNumber==nil){ return; }
    
    [_phoneNumberTextField resignFirstResponder];

    Future* futureFinished = [self asyncRegister:localNumber untilCancelled:[life getToken]];
    [_registerActivityIndicator startAnimating];
    _registerButton.enabled = NO;
    _registerErrorLabel.text = @"";
    [futureFinished catchDo:^(id error) {
        [_challengeActivityIndicator stopAnimating];
        _registerButton.enabled = YES;
        // todo: localize
        _registerErrorLabel.text = [error description];
    }];
}

- (void)dismissTapped {
    [self dismissView];
}

- (void)verifyChallengeTapped {
    [_challengeTextField resignFirstResponder];
    _challengeButton.enabled = NO;
    [_challengeActivityIndicator startAnimating];

    HttpRequest *verifyRequest = [HttpRequest httpRequestToVerifyAccessToPhoneNumberWithChallenge:_challengeTextField.text];
    Future *futureDone = [HttpManager asyncOkResponseFromMasterServer:verifyRequest
                                                      unlessCancelled:nil
                                                      andErrorHandler:[Environment errorNoter]];

    _challengeErrorLabel.text = @"";
    [futureDone catchDo:^(id error) {
        if ([error isKindOfClass:[HttpResponse class]]) {
            HttpResponse* badResponse = error;
            if ([badResponse getStatusCode] == 401) {
                // @todo: human readable, localizable
                _challengeErrorLabel.text = @"Incorrect Challenge Code";
                return;
            }
        }
        [Environment errorNoter](error, @"While Verifying Challenge.", NO);
        // @todo: human readable, localizable
        _challengeErrorLabel.text = [NSString stringWithFormat:@"Unexpected failure: %@", error];
    }];

    [futureDone thenDo:^(id result) {
        [[Environment preferences] setIsRegistered:YES];
        [[[Environment getCurrent] phoneDirectoryManager] forceUpdate];
        [registered trySetResult:@YES];
        [self dismissView];
        [futureChallengeAcceptedSource trySetResult:result];
    }];

    [futureDone finallyDo:^(Future *completed) {
        _challengeButton.enabled = YES;
        [_challengeActivityIndicator stopAnimating];
    }];
}

- (void)showViewNumber:(NSInteger)viewNumber {

    
    if (viewNumber == REGISTER_VIEW_NUMBER) {
        [_registerActivityIndicator stopAnimating];
        _registerButton.enabled = YES;
    }
    
    [self stopVoiceVerificationCountdownTimer];
    
    [_scrollView setContentOffset:CGPointMake(_scrollView.frame.size.width*viewNumber, 0) animated:YES];
}

- (void)presentInvalidCountryCodeError {
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:REGISTER_CC_ERR_ALERT_VIEW_TITLE
                                                        message:REGISTER_CC_ERR_ALERT_VIEW_MESSAGE
                                                       delegate:nil
                                              cancelButtonTitle:REGISTER_CC_ERR_ALERT_VIEW_DISMISS
                                              otherButtonTitles:nil];
    [alertView show];
}

- (void) startVoiceVerificationCountdownTimer{
    [self.initiateVoiceVerificationButton.titleLabel setTextAlignment:NSTextAlignmentCenter];
    self.initiateVoiceVerificationButton.hidden = NO;
    
    NSTimeInterval smsTimeoutTimeInterval = SMS_VERIFICATION_TIMEOUT_SECONDS;
    
    NSDate *now = [[NSDate alloc] init];
    timeoutDate = [[NSDate alloc] initWithTimeInterval:smsTimeoutTimeInterval sinceDate:now];

    countdownTimer = [NSTimer scheduledTimerWithTimeInterval:1
                                                      target:self
                                                    selector:@selector(countdowntimerFired)
                                                    userInfo:nil repeats:YES];
}

- (void) stopVoiceVerificationCountdownTimer{
    [countdownTimer invalidate];
}

- (void) countdowntimerFired {
    NSDate *now = [[NSDate alloc] init];
    
    NSCalendar *sysCalendar = [NSCalendar currentCalendar];
    unsigned int unitFlags = NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit;
    NSDateComponents *conversionInfo = [sysCalendar components:unitFlags fromDate:now  toDate:timeoutDate  options:0];
    NSString* timeLeft = [NSString stringWithFormat:@"%d:%02d",[conversionInfo minute],[conversionInfo second]];

    [self.voiceChallengeTextLabel setText:timeLeft];

    if (0 <= [now  compare:timeoutDate]) {
        [self initiateVoiceVerification];
    }
    
}

- (void) initiateVoiceVerification{
    [self stopVoiceVerificationCountdownTimer];
    CancellableOperationStarter callStarter = ^Future *(id<CancelToken> internalUntilCancelledToken) {
        HttpRequest* voiceVerifyReq = [HttpRequest httpRequestToStartRegistrationOfPhoneNumberWithVoice];
        
        [self.voiceChallengeTextLabel setText:@"Calling" ];
        return [HttpManager asyncOkResponseFromMasterServer:voiceVerifyReq
                                            unlessCancelled:internalUntilCancelledToken
                                            andErrorHandler:[Environment errorNoter]];
    };
    Future *futureVoiceVerificationStarted = [AsyncUtil raceCancellableOperation:callStarter
                                                                  againstTimeout:SERVER_TIMEOUT_SECONDS
                                                                  untilCancelled:[life getToken]];
    [futureVoiceVerificationStarted catchDo:^(id errorId) {
        HttpResponse* error = (HttpResponse*)errorId;
       [self.voiceChallengeTextLabel setText:[error getStatusText]];
    }];
    
    [futureVoiceVerificationStarted finally:^id(id _id) {
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, VOICE_VERIFICATION_COOLDOWN_SECONDS * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [self.voiceChallengeTextLabel setText:@"Re-Call"];
        });
        
        return _id;
    }];
    
    
}

- (IBAction)initiateVoiceVerificationButtonHandler {
    [self initiateVoiceVerification];
}

#pragma mark - Keyboard notifications

- (void)initializeKeyboardHandlers{
    UITapGestureRecognizer *outsideTabRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboardFromAppropriateSubView)];
    [self.view addGestureRecognizer:outsideTabRecognizer];

    [self observeKeyboardNotifications];
    
}

-(void) dismissKeyboardFromAppropriateSubView {
    [self.view endEditing:NO];
}

- (void)observeKeyboardNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    double duration = [[[notification userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        CGSize keyboardSize = [[[notification userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;;
        _scrollView.frame = CGRectMake(CGRectGetMinX(_scrollView.frame),
                                       CGRectGetMinY(_scrollView.frame)-keyboardSize.height,
                                       CGRectGetWidth(_scrollView.frame),
                                       CGRectGetHeight(_scrollView.frame));
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    double duration = [[[notification userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        _scrollView.frame = CGRectMake(CGRectGetMinX(_scrollView.frame),
                                       CGRectGetMinY(self.view.frame),
                                       CGRectGetWidth(_scrollView.frame),
                                       CGRectGetHeight(_scrollView.frame));
    }];
}

#pragma mark - CountryCodeViewControllerDelegate

- (void)countryCodeViewController:(CountryCodeViewController *)vc
             didSelectCountryCode:(NSString *)code
                       forCountry:(NSString *)country {
    _countryCodeLabel.text = code;
    _countryNameLabel.text = country;
    [self updatePhoneNumberFieldWithString:code];
    [vc dismissViewControllerAnimated:YES completion:nil];
}

- (void)countryCodeViewControllerDidCancel:(CountryCodeViewController *)vc {
    [vc dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range
                                                       replacementString:(NSString *)string {
    
    BOOL handleBackspace = range.length == 1;
    if (handleBackspace) {
        NSRange backspaceRange = NSMakeRange([_enteredPhoneNumber length] - 1, 1);
        [_enteredPhoneNumber replaceCharactersInRange:backspaceRange withString:string];
    } else {
        NSString* sanitizedString = [[string componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet ] invertedSet]] componentsJoinedByString:@""];
        [_enteredPhoneNumber appendString:sanitizedString];
    }

    [self updatePhoneNumberFieldWithString:_enteredPhoneNumber];
    return NO;
}

-(void) updatePhoneNumberFieldWithString:(NSString*) input {
    NSString* result = [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:_enteredPhoneNumber
                                                                    withSpecifiedCountryCodeString:_countryCodeLabel.text];
    _phoneNumberTextField.text = result;
}

@end
