//
//  CodeVerificationViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "CodeVerificationViewController.h"

#import <TextSecureKit/TSStorageManager+keyingMaterial.h>
#import "ContactsManager.h"
#import "Environment.h"
#import "LocalizableText.h"
#import "PushManager.h"
#import "RPAccountManager.h"
#import "RPServerRequestsManager.h"
#import "TSAccountManager.h"

@interface CodeVerificationViewController ()

@end

@implementation CodeVerificationViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self initializeKeyboardHandlers];
    _headerLabel.text               = NSLocalizedString(@"VERIFICATION_HEADER", @"");
    _challengeTextField.placeholder = NSLocalizedString(@"VERIFICATION_CHALLENGE_DEFAULT_TEXT", @"");
    _challengeTextField.delegate    = self;
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

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self enableServerActions:YES];
    [_phoneNumberEntered setText:_formattedPhoneNumber];
    [self adjustScreenSizes];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}


- (IBAction)verifyChallengeAction:(id)sender {
    [self enableServerActions:NO];
    [_challengeTextField resignFirstResponder];

    [self registerWithSuccess:^{
      [_submitCodeSpinner stopAnimating];

      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [TSAccountManager didRegister];
        dispatch_async(dispatch_get_main_queue(), ^{
          [self.navigationController
              dismissViewControllerAnimated:YES
                                 completion:^{
                                   if (ABAddressBookGetAuthorizationStatus() == kABAuthorizationStatusNotDetermined ||
                                       ABAddressBookGetAuthorizationStatus() == kABAuthorizationStatusRestricted) {
                                       UIAlertController *controller = [UIAlertController
                                           alertControllerWithTitle:NSLocalizedString(@"REGISTER_CONTACTS_WELCOME", nil)
                                                            message:NSLocalizedString(@"REGISTER_CONTACTS_BODY", nil)
                                                     preferredStyle:UIAlertControllerStyleAlert];

                                       [controller addAction:[UIAlertAction
                                                                 actionWithTitle:NSLocalizedString(
                                                                                     @"REGISTER_CONTACTS_CONTINUE", nil)
                                                                           style:UIAlertActionStyleDefault
                                                                         handler:^(UIAlertAction *action) {
                                                                           [self setupContacts];
                                                                         }]];

                                       [[UIApplication sharedApplication]
                                               .keyWindow.rootViewController presentViewController:controller
                                                                                          animated:YES
                                                                                        completion:nil];

                                   } else {
                                       [self setupContacts];
                                   }

                                 }];
        });
      });
    }
        failure:^(NSError *error) {
          [self enableServerActions:YES];
          [_submitCodeSpinner stopAnimating];
          DDLogError(@"Error: %@", error.localizedDescription);
        }];
}

- (void)setupContacts {
    [[Environment getCurrent].contactsManager doAfterEnvironmentInitSetup];

    [[PushManager sharedManager] validateUserNotificationSettings];
}

- (NSString *)validationCodeFromTextField {
    return [_challengeTextField.text stringByReplacingOccurrencesOfString:@"-" withString:@""];
}

- (TOCFuture *)pushRegistration {
    TOCFutureSource *pushAndRegisterFuture = [[TOCFutureSource alloc] init];
    ;
    [[PushManager sharedManager] requestPushTokenWithSuccess:^(NSString *pushToken, NSString *voipToken) {
      NSMutableArray *pushTokens = [NSMutableArray arrayWithObject:pushToken];

      if (voipToken) {
          [pushTokens addObject:voipToken];
      }

      [pushAndRegisterFuture trySetResult:pushTokens];
    }
        failure:^(NSError *error) {
          [pushAndRegisterFuture trySetFailure:error];
        }];

    return pushAndRegisterFuture.future;
}

- (TOCFuture *)textSecureRegistrationFuture:(NSArray *)pushTokens {
    TOCFutureSource *textsecureRegistration = [[TOCFutureSource alloc] init];

    [TSAccountManager verifyAccountWithCode:[self validationCodeFromTextField]
        pushToken:pushTokens[0]
        voipToken:([pushTokens count] == 2) ? pushTokens.lastObject : nil
        supportsVoice:YES
        success:^{
          [textsecureRegistration trySetResult:@YES];
        }
        failure:^(NSError *error) {
          [textsecureRegistration trySetFailure:error];
        }];

    return textsecureRegistration.future;
}


- (void)registerWithSuccess:(void (^)())success failure:(void (^)(NSError *))failure {
    [_submitCodeSpinner startAnimating];

    __block NSArray<NSString *> *pushTokens;

    TOCFuture *tsRegistrationFuture = [[self pushRegistration] then:^id(NSArray<NSString *> *tokens) {
      pushTokens = tokens;
      return [self textSecureRegistrationFuture:pushTokens];
    }];

    TOCFuture *redphoneRegistrationFuture = [tsRegistrationFuture then:^id(id value) {
      return [[self getRPRegistrationToken] then:^(NSString *registrationFuture) {
        return [self redphoneRegistrationWithTSToken:registrationFuture
                                           pushToken:pushTokens[0]
                                           voipToken:([pushTokens count] == 2) ? pushTokens.lastObject : nil];
      }];
    }];

    [redphoneRegistrationFuture thenDo:^(id value) {
      success();
    }];

    [redphoneRegistrationFuture catchDo:^(NSError *error) {
      failure(error);
    }];
}


- (TOCFuture *)getRPRegistrationToken {
    TOCFutureSource *redPhoneTokenFuture = [[TOCFutureSource alloc] init];

    [TSAccountManager obtainRPRegistrationToken:^(NSString *rpRegistrationToken) {
      [redPhoneTokenFuture trySetResult:rpRegistrationToken];
    }
        failure:^(NSError *error) {
          [redPhoneTokenFuture trySetFailure:error];
        }];

    return redPhoneTokenFuture.future;
}

- (TOCFuture *)redphoneRegistrationWithTSToken:(NSString *)tsToken
                                     pushToken:(NSString *)pushToken
                                     voipToken:(NSString *)voipToken {
    TOCFutureSource *rpRegistration = [[TOCFutureSource alloc] init];

    [RPAccountManager registrationWithTsToken:tsToken
        pushToken:pushToken
        voipToken:voipToken
        success:^{
          [rpRegistration trySetResult:@YES];
        }
        failure:^(NSError *error) {
          [rpRegistration trySetFailure:error];
        }];

    return rpRegistration.future;
}

#pragma mark - Send codes again
- (IBAction)sendCodeSMSAction:(id)sender {
    [self enableServerActions:NO];

    [_requestCodeAgainSpinner startAnimating];
    [TSAccountManager rerequestSMSWithSuccess:^{
      [self enableServerActions:YES];
      [_requestCodeAgainSpinner stopAnimating];
    }
        failure:^(NSError *error) {
          [self showRegistrationErrorMessage:error];
          [self enableServerActions:YES];
          [_requestCodeAgainSpinner stopAnimating];
        }];
}

- (IBAction)sendCodeVoiceAction:(id)sender {
    [self enableServerActions:NO];

    [_requestCallSpinner startAnimating];
    [TSAccountManager rerequestVoiceWithSuccess:^{
      [self enableServerActions:YES];
      [_requestCallSpinner stopAnimating];
    }
        failure:^(NSError *error) {
          [self showRegistrationErrorMessage:error];
          [self enableServerActions:YES];
          [_requestCallSpinner stopAnimating];
        }];
}

- (void)showRegistrationErrorMessage:(NSError *)registrationError {
    UIAlertView *registrationErrorAV = [[UIAlertView alloc] initWithTitle:registrationError.localizedDescription
                                                                  message:registrationError.localizedRecoverySuggestion
                                                                 delegate:nil
                                                        cancelButtonTitle:REGISTER_ERROR_ALERT_VIEW_DISMISS
                                                        otherButtonTitles:nil, nil];

    [registrationErrorAV show];
}

- (void)enableServerActions:(BOOL)enabled {
    [_challengeButton setEnabled:enabled];
    [_sendCodeViaSMSAgainButton setEnabled:enabled];
    [_sendCodeViaVoiceButton setEnabled:enabled];
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

    if (range.length == 0 && range.location == 3) {
        textField.text = [NSString stringWithFormat:@"%@-%@", textField.text, string];
        return NO;
    }

    if (range.length == 1 && range.location == 4) {
        range.location--;
        range.length   = 2;
        textField.text = [textField.text stringByReplacingCharactersInRange:range withString:@""];
        return NO;
    }

    return YES;
}

- (void)adjustScreenSizes {
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    CGFloat blueHeaderHeight;

    if (screenHeight < 667) {
        self.signalLogo.hidden = YES;
        blueHeaderHeight       = screenHeight - 400;
    } else {
        blueHeaderHeight = screenHeight - 410;
    }

    _headerConstraint.constant = blueHeaderHeight;
}

@end
