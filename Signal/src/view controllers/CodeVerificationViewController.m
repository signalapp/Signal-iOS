//
//  CodeVerificationViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "CodeVerificationViewController.h"

#import "Environment.h"
#import "PhoneNumberDirectoryFilterManager.h"
#import "RPServerRequestsManager.h"
#import "LocalizableText.h"
#import "PushManager.h"
#import "SignalKeyingStorage.h"
#import "TSAccountManager.h"

@interface CodeVerificationViewController ()

@end

@implementation CodeVerificationViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    [self initializeKeyboardHandlers];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (IBAction)verifyChallengeAction:(id)sender {
    
    [_challengeTextField resignFirstResponder];
    //TODO: Lock UI interactions
    
    [self registerWithSuccess:^{
        [Environment.getCurrent.phoneDirectoryManager forceUpdate];
        [self performSegueWithIdentifier:@"verifiedSegue" sender:self];
    } failure:^(NSError *error) {
       // TODO: Unlock UI
        NSLog(@"Failed to register");
        [self showAlertForError:error];
    }];
}


- (void)registerWithSuccess:(void(^)())success failure:(void(^)(NSError *))failure{
    //TODO: Refactor this to use futures? Better error handling needed. Good enough for PoC
    
    [[RPServerRequestsManager sharedInstance] performRequest:[RPAPICall verifyVerificationCode:_challengeTextField.text] success:^(NSURLSessionDataTask *task, id responseObject) {
        
        [PushManager.sharedManager registrationAndRedPhoneTokenRequestWithSuccess:^(NSData *pushToken, NSString *signupToken) {
            
            [TSAccountManager registerWithRedPhoneToken:signupToken pushToken:pushToken success:^{
                success();
            } failure:^(NSError *error) {
                failure(error);
            }];
        } failure:^{
            // PushManager shows its own error alerts, so we don't want to show a second one
            failure(nil);
        }];
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSHTTPURLResponse* badResponse = (NSHTTPURLResponse*)task.response;
        NSError *responseError = [self errorForResponse:badResponse];
        
        failure(responseError);
    }];
}


// TODO: If useful, this could possibly go in a less-specific class
- (void)showAlertForError:(NSError *)error {
    
    if (error == nil) {
        NSLog(@"%@: Error condition, but no NSError to display", self.class);
        return;
    } else if (error.localizedDescription.length == 0) {
        NSLog(@"%@: Unable to display error because localizedDescription was not set: %@", self.class, error);
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


- (NSError *)errorForResponse:(NSHTTPURLResponse *)badResponse {
    
    NSString *description = NSLocalizedString(@"REGISTRATION_ERROR", @"");
    NSString *failureReason = nil;
    TSRegistrationFailure failureType;
    
    if (badResponse.statusCode == 401) {
        failureReason = REGISTER_CHALLENGE_ALERT_VIEW_BODY;
        failureType = kTSRegistrationFailureAuthentication;
    } else if (badResponse.statusCode == 413){
        failureReason = NSLocalizedString(@"REGISTER_RATE_LIMITING_BODY", @"");
        failureType = kTSRegistrationFailureRateLimit;
    } else {
        failureReason = [NSString stringWithFormat:@"%@ %lu", NSLocalizedString(@"SERVER_CODE", @""),(unsigned long)badResponse.statusCode];
        failureType = kTSRegistrationFailureNetwork;
    }
    
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey: description, NSLocalizedFailureReasonErrorKey: failureReason};
    NSError *error = [NSError errorWithDomain:TSRegistrationErrorDomain code:failureType userInfo:userInfo];
    
    return error;
}


#pragma mark - Keyboard notifications

- (void)initializeKeyboardHandlers{
    UITapGestureRecognizer *outsideTabRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboardFromAppropriateSubView)];
    [self.view addGestureRecognizer:outsideTabRecognizer];
        
}

- (void)dismissKeyboardFromAppropriateSubView {
    [self.view endEditing:NO];
}

@end
