//
//  RegistrationViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "CountryCodeViewController.h"


@interface RegistrationViewController : UIViewController <UITextFieldDelegate>

// Country code
@property (nonatomic, strong) IBOutlet UIButton *countryNameButton;
@property (nonatomic, strong) IBOutlet UIButton *countryCodeButton;

// Phone number
@property (nonatomic, strong) IBOutlet UITextField *phoneNumberTextField;
@property (nonatomic, strong) IBOutlet UIButton *phoneNumberButton;
@property (nonatomic, strong) IBOutlet UILabel *titleLabel;
// Button
@property (nonatomic, strong) IBOutlet UIButton *sendCodeButton;

@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *spinnerView;
@property (nonatomic) IBOutlet UIImageView *signalLogo;
@property (nonatomic) IBOutlet UIView *registrationHeader;

@property (nonatomic) IBOutlet NSLayoutConstraint *headerHeightConstraint;

- (IBAction)unwindToCountryCodeWasSelected:(UIStoryboardSegue *)segue;
- (IBAction)unwindToCountryCodeSelectionCancelled:(UIStoryboardSegue *)segue;

@end
