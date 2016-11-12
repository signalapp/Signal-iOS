//
//  CodeVerificationViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
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

@interface CodeVerificationViewController ()

@property (nonatomic, strong, readonly) AccountManager *accountManager;

@end

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
    [self initializeKeyboardHandlers];
    _headerLabel.text               = NSLocalizedString(@"VERIFICATION_HEADER", @"Navigation title in the registration flow - during the sms code verification process.");
    _challengeTextField.placeholder = NSLocalizedString(@"VERIFICATION_CHALLENGE_DEFAULT_TEXT",
        @"Text field placeholder for SMS verification code during registration");
    _challengeTextField.delegate    = self;
    [_challengeButton setTitle:NSLocalizedString(@"VERIFICATION_CHALLENGE_SUBMIT_CODE", @"button text during registration to submit your SMS verification code")
                      forState:UIControlStateNormal];

    [_sendCodeViaSMSAgainButton setTitle:NSLocalizedString(@"VERIFICATION_CHALLENGE_SUBMIT_AGAIN", @"button text during registration to request another SMS code be sent")
                                forState:UIControlStateNormal];
    [_sendCodeViaVoiceButton
        setTitle:[@"     " stringByAppendingString:NSLocalizedString(@"VERIFICATION_CHALLENGE_SEND_VIAVOICE", @"button text during registration to request phone number verification be done via phone call")]
        forState:UIControlStateNormal];
    [_changeNumberButton
        setTitle:[@"     " stringByAppendingString:NSLocalizedString(@"VERIFICATION_CHALLENGE_CHANGE_NUMBER", @"button text during registration to make corrections to your submitted phone number")]
        forState:UIControlStateNormal];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self enableServerActions:YES];
    [_phoneNumberEntered setText:
        [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:[TSAccountManager localNumber]]];
    [self adjustScreenSizes];
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

- (IBAction)verifyChallengeAction:(id)sender
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
                                                          handler:nil];
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
- (IBAction)sendCodeSMSAction:(id)sender {
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

- (IBAction)sendCodeVoiceAction:(id)sender {
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

- (void)adjustScreenSizes
{
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;

    if (screenHeight < 667) { // iphone 5
        self.signalLogo.hidden = YES;
        _headerConstraint.constant = 120;
    }
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
