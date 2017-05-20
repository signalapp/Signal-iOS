//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "CountryCodeViewController.h"


@interface RegistrationViewController : UIViewController <UITextFieldDelegate>

// Country code
@property (nonatomic) IBOutlet UIButton *countryNameButton;
@property (nonatomic) IBOutlet UIButton *countryCodeButton;
@property (nonatomic) IBOutlet UIView *countryCodeRow;

// Phone number
@property (nonatomic) IBOutlet UITextField *phoneNumberTextField;
@property (nonatomic) IBOutlet UIButton *phoneNumberButton;
@property (nonatomic) IBOutlet UILabel *titleLabel;
// Button
@property (nonatomic) IBOutlet UIButton *sendCodeButton;
@property (nonatomic) IBOutlet UIButton *existingUserButton;

@property (nonatomic) IBOutlet UIActivityIndicatorView *spinnerView;
@property (nonatomic) IBOutlet UIImageView *signalLogo;
@property (nonatomic) IBOutlet UIView *registrationHeader;

@property (nonatomic) IBOutlet NSLayoutConstraint *headerHeightConstraint;

- (IBAction)unwindToCountryCodeWasSelected:(UIStoryboardSegue *)segue;
- (IBAction)unwindToCountryCodeSelectionCancelled:(UIStoryboardSegue *)segue;

@end
