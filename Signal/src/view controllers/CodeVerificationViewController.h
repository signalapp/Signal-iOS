//
//  CodeVerificationViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//
// This class allows the user to send the server their verification code and request new codes to be sent via SMS or
// voice.
//

#import <UIKit/UIKit.h>

@interface CodeVerificationViewController : UIViewController <UITextFieldDelegate>

@property (nonatomic, strong) IBOutlet UIImageView *signalLogo;

// Where the user enters the verification code they wish to document
@property (nonatomic, strong) IBOutlet UITextField *challengeTextField;

@property (nonatomic, strong) NSString *formattedPhoneNumber;

@property (nonatomic, strong) IBOutlet UILabel *headerLabel;
// User action buttons
@property (nonatomic, strong) IBOutlet UIButton *challengeButton;
@property (nonatomic, strong) IBOutlet UIButton *sendCodeViaSMSAgainButton;
@property (nonatomic, strong) IBOutlet UIButton *sendCodeViaVoiceButton;

@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *submitCodeSpinner;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *requestCodeAgainSpinner;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *requestCallSpinner;
@property (nonatomic, strong) IBOutlet UIButton *changeNumberButton;
@property (nonatomic) IBOutlet NSLayoutConstraint *headerConstraint;

// Displays phone number entered in previous step. There is a UI option (segue) which allows the user to go back and
// edit this.
@property (nonatomic, strong) IBOutlet UILabel *phoneNumberEntered;


// User verifies code
- (IBAction)verifyChallengeAction:(id)sender;
// User requests new code via SMS
- (IBAction)sendCodeSMSAction:(id)sender;
// User requests new code via voice phone call
- (IBAction)sendCodeVoiceAction:(id)sender;

// This ensures the user doesn't keep creating server requests before the server has responded for all buttons that
// result in server requests
- (void)enableServerActions:(BOOL)enabled;

@end
