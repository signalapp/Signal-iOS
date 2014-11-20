//
//  CodeVerificationViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "CodeVerificationViewController.h"

#import "RPServerRequestsManager.h"
#import "LocalizableText.h"
#import "PushManager.h"
#import "SGNKeychainUtil.h"
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
    
    [[RPServerRequestsManager sharedInstance] performRequest:[RPAPICall verifyVerificationCode:_challengeTextField.text] success:^(NSURLSessionDataTask *task, id responseObject) {
        
        [PushManager.sharedManager registrationAndRedPhoneTokenRequestWithSuccess:^(NSData *pushToken, NSString *signupToken) {
            [TSAccountManager registerWithRedPhoneToken:signupToken pushToken:pushToken success:^{
                 [self performSegueWithIdentifier:@"verifiedSegue" sender:self];
            } failure:^(TSRegistrationFailure failureType) {
                NSLog(@":(");
            }];
        } failure:^{
            
        }];
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSString *alertTitle = NSLocalizedString(@"REGISTRATION_ERROR", @"");
        
        NSHTTPURLResponse* badResponse = (NSHTTPURLResponse*)task.response;
        if (badResponse.statusCode == 401) {
            SignalAlertView(alertTitle, REGISTER_CHALLENGE_ALERT_VIEW_BODY);
        } else if (badResponse.statusCode == 413){
            SignalAlertView(alertTitle, NSLocalizedString(@"REGISTER_RATE_LIMITING_BODY", @""));
        } else {
            NSString *alertBodyString = [NSString stringWithFormat:@"%@ %lu", NSLocalizedString(@"SERVER_CODE", @""),(unsigned long)badResponse.statusCode];
            SignalAlertView (alertTitle, alertBodyString);
        }
    }];
}

#pragma mark - Keyboard notifications

- (void)initializeKeyboardHandlers{
    UITapGestureRecognizer *outsideTabRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboardFromAppropriateSubView)];
    [self.view addGestureRecognizer:outsideTabRecognizer];
        
}

- (void)dismissKeyboardFromAppropriateSubView {
    [self.view endEditing:NO];
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
