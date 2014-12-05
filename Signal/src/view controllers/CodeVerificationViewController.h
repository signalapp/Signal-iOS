//
//  CodeVerificationViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface CodeVerificationViewController : UIViewController

@property(nonatomic, strong) IBOutlet UITextField* challengeTextField;

@property (nonatomic, strong) IBOutlet UILabel* phoneNumberEntered;

@property(nonatomic, strong) IBOutlet UIButton* challengeButton;

@property(nonatomic, strong) IBOutlet UIButton* sendCodeViaSMSAgainButton;

@property(nonatomic, strong) IBOutlet UIButton* sendCodeViaVoiceButton;

- (IBAction)verifyChallengeAction:(id)sender;
- (IBAction)sendCodeSMSAction:(id)sender;
- (IBAction)sendCodeVoiceAction:(id)sender;

@end
