//
//  CodeVerificationViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "CodeVerificationViewController.h"

#import "Environment.h"
#import "ContactsManager.h"
#import "PhoneNumberDirectoryFilterManager.h"
#import "RPServerRequestsManager.h"
#import "LocalizableText.h"
#import "PushManager.h"
#import "TSAccountManager.h"

@interface CodeVerificationViewController ()

@end

@implementation CodeVerificationViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self initializeKeyboardHandlers];
    _headerLabel.text = NSLocalizedString(@"VERIFICATION_HEADER", @"");
    _challengeTextField.placeholder = NSLocalizedString(@"VERIFICATION_CHALLENGE_DEFAULT_TEXT", @"");
    [_challengeButton setTitle:NSLocalizedString(@"VERIFICATION_CHALLENGE_SUBMIT_CODE", @"")
                      forState:UIControlStateNormal];
    
    [_sendCodeViaSMSAgainButton setTitle:NSLocalizedString(@"VERIFICATION_CHALLENGE_SUBMIT_AGAIN", @"")
                                forState:UIControlStateNormal];
    [_sendCodeViaVoiceButton
     setTitle:[@"     " stringByAppendingString:NSLocalizedString(@"VERIFICATION_CHALLENGE_SEND_VIAVOICE", @"")]
     forState:UIControlStateNormal];
    [_changeNumberButton
     setTitle:[@"     " stringByAppendingString:NSLocalizedString(@"VERIFICATION_CHALLENGE_CHANGE_NUMBER", @"")]
     forState:UIControlStateNormal];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self enableServerActions:YES];
    [_phoneNumberEntered setText:_formattedPhoneNumber];
    [self adjustScreenSizes];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}


- (IBAction)verifyChallengeAction:(id)sender
{
    [self enableServerActions:NO];
    [_challengeTextField resignFirstResponder];
    
    [self registerWithSuccess:^{
        [_submitCodeSpinner stopAnimating];
        [Environment.getCurrent.phoneDirectoryManager forceUpdate];
        
        [self.navigationController dismissViewControllerAnimated:YES completion:^{
            [self passedVerification];
        }];
    } failure:^(NSError *error) {
        [self showAlertForError:error];
        [self enableServerActions:YES];
        [_submitCodeSpinner stopAnimating];
    }];
}

- (void)passedVerification {
    if (ABAddressBookGetAuthorizationStatus() == kABAuthorizationStatusNotDetermined ||
        ABAddressBookGetAuthorizationStatus() == kABAuthorizationStatusRestricted) {
        UIAlertController *controller = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"REGISTER_CONTACTS_WELCOME", nil)
                                                                            message:NSLocalizedString(@"REGISTER_CONTACTS_BODY", nil)
                                                                     preferredStyle:UIAlertControllerStyleAlert];
        
        [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"REGISTER_CONTACTS_CONTINUE", nil)
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction *action) {
                                                         [self setupContacts];
                                                     }]];
        
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:controller animated:YES completion:nil];
        
    } else {
        [self setupContacts];
    }
}

- (void)setupContacts {
    [[Environment getCurrent].contactsManager doAfterEnvironmentInitSetup];
}

- (void)registerWithSuccess:(void (^)())success failure:(void (^)(NSError *))failure
{
    [_submitCodeSpinner startAnimating];
    [[RPServerRequestsManager sharedInstance] performRequest:[RPAPICall verifyVerificationCode:_challengeTextField.text]
                                                     success:^(NSURLSessionDataTask *task, id responseObject) {
                                                         
                                                         [PushManager.sharedManager registrationAndRedPhoneTokenRequestWithSuccess:^(NSData *pushToken, NSData *voipToken, NSString *signupToken) {
                                                             [TSAccountManager registerWithRedPhoneToken:signupToken
                                                                                               pushToken:pushToken
                                                                                               voipToken:voipToken
                                                                                                 success:^{
                                                                                                     success();
                                                                                                 }
                                                                                                 failure:^(NSError *error) {
                                                                                                     failure(error);
                                                                                                 }];
                                                         } failure:^(NSError *error) {
                                                             failure(error);
                                                             [_submitCodeSpinner stopAnimating];
                                                         }];
                                                     }
                                                     failure:^(NSURLSessionDataTask *task, NSError *error) {
                                                         NSHTTPURLResponse *badResponse = (NSHTTPURLResponse *)task.response;
                                                         NSError *responseError = [self errorForResponse:badResponse];
                                                         
                                                         failure(responseError);
                                                         [_submitCodeSpinner stopAnimating];
                                                         
                                                     }];
}


// TODO: If useful, this could possibly go in a less-specific class
- (void)showAlertForError:(NSError *)error
{
    if (error == nil) {
        DDLogError(@"%@: Error condition, but no NSError to display", self.class);
        return;
    } else if (error.localizedDescription.length == 0) {
        DDLogError(@"%@: Unable to display error because localizedDescription was not set: %@", self.class, error);
        return;
    }
    
    NSString *alertBody = nil;
    if (error.localizedFailureReason.length > 0) {
        alertBody = error.localizedFailureReason;
    } else if (error.localizedRecoverySuggestion.length > 0) {
        alertBody = error.localizedRecoverySuggestion;
    }
    
    SignalAlertView(error.localizedDescription, alertBody);
}


- (NSError *)errorForResponse:(NSHTTPURLResponse *)badResponse
{
    NSString *description = NSLocalizedString(@"REGISTRATION_ERROR", @"");
    NSString *failureReason = nil;
    TSRegistrationFailure failureType;
    
    if (badResponse.statusCode == 401) {
        failureReason = REGISTER_CHALLENGE_ALERT_VIEW_BODY;
        failureType = kTSRegistrationFailureAuthentication;
    } else if (badResponse.statusCode == 413) {
        failureReason = NSLocalizedString(@"REGISTER_RATE_LIMITING_BODY", @"");
        failureType = kTSRegistrationFailureRateLimit;
    } else {
        failureReason = [NSString
                         stringWithFormat:@"%@ %lu", NSLocalizedString(@"SERVER_CODE", @""), (unsigned long)badResponse.statusCode];
        failureType = kTSRegistrationFailureNetwork;
    }
    
    NSDictionary *userInfo =
    @{NSLocalizedDescriptionKey : description, NSLocalizedFailureReasonErrorKey : failureReason};
    NSError *error = [NSError errorWithDomain:TSRegistrationErrorDomain code:failureType userInfo:userInfo];
    
    return error;
}

#pragma mark - Send codes again
- (IBAction)sendCodeSMSAction:(id)sender
{
    [self enableServerActions:NO];
    
    [_requestCodeAgainSpinner startAnimating];
    [[RPServerRequestsManager sharedInstance] performRequest:[RPAPICall requestVerificationCode]
                                                     success:^(NSURLSessionDataTask *task, id responseObject) {
                                                         [self enableServerActions:YES];
                                                         [_requestCodeAgainSpinner stopAnimating];
                                                         
                                                     }
                                                     failure:^(NSURLSessionDataTask *task, NSError *error) {
                                                         
                                                         DDLogError(@"Registration failed with information %@", error.description);
                                                         
                                                         UIAlertView *registrationErrorAV = [[UIAlertView alloc] initWithTitle:REGISTER_ERROR_ALERT_VIEW_TITLE
                                                                                                                       message:REGISTER_ERROR_ALERT_VIEW_BODY
                                                                                                                      delegate:nil
                                                                                                             cancelButtonTitle:REGISTER_ERROR_ALERT_VIEW_DISMISS
                                                                                                             otherButtonTitles:nil, nil];
                                                         
                                                         [registrationErrorAV show];
                                                         
                                                         [self enableServerActions:YES];
                                                         [_requestCodeAgainSpinner stopAnimating];
                                                     }];
}

- (IBAction)sendCodeVoiceAction:(id)sender
{
    [self enableServerActions:NO];
    
    [_requestCallSpinner startAnimating];
    [[RPServerRequestsManager sharedInstance] performRequest:[RPAPICall requestVerificationCodeWithVoice]
                                                     success:^(NSURLSessionDataTask *task, id responseObject) {
                                                         
                                                         [self enableServerActions:YES];
                                                         [_requestCallSpinner stopAnimating];
                                                         
                                                     }
                                                     failure:^(NSURLSessionDataTask *task, NSError *error) {
                                                         
                                                         DDLogError(@"Registration failed with information %@", error.description);
                                                         
                                                         UIAlertView *registrationErrorAV = [[UIAlertView alloc] initWithTitle:REGISTER_ERROR_ALERT_VIEW_TITLE
                                                                                                                       message:REGISTER_ERROR_ALERT_VIEW_BODY
                                                                                                                      delegate:nil
                                                                                                             cancelButtonTitle:REGISTER_ERROR_ALERT_VIEW_DISMISS
                                                                                                             otherButtonTitles:nil, nil];
                                                         
                                                         [registrationErrorAV show];
                                                         [self enableServerActions:YES];
                                                         [_requestCallSpinner stopAnimating];
                                                     }];
}

- (void)enableServerActions:(BOOL)enabled
{
    [_challengeButton setEnabled:enabled];
    [_sendCodeViaSMSAgainButton setEnabled:enabled];
    [_sendCodeViaVoiceButton setEnabled:enabled];
}


#pragma mark - Keyboard notifications

- (void)initializeKeyboardHandlers
{
    UITapGestureRecognizer *outsideTabRecognizer =
    [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboardFromAppropriateSubView)];
    [self.view addGestureRecognizer:outsideTabRecognizer];
}

- (void)dismissKeyboardFromAppropriateSubView
{
    [self.view endEditing:NO];
}

- (void)adjustScreenSizes
{
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    CGFloat blueHeaderHeight;
    
    if (screenHeight < 667) {
        self.signalLogo.hidden = YES;
        blueHeaderHeight = screenHeight - 400;
    } else {
        blueHeaderHeight = screenHeight - 410;
    }
    
    _headerConstraint.constant = blueHeaderHeight;
}

@end
