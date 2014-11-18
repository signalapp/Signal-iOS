#import <UIKit/UIKit.h>

#import "CollapsingFutures.h"
#import "CountryCodeViewController.h"

@interface RegisterViewController : UIViewController <CountryCodeViewControllerDelegate, UITextFieldDelegate>

@property (strong, nonatomic) IBOutlet UIButton* registerButton;
@property (strong, nonatomic) IBOutlet UIButton* challengeButton;
@property (strong, nonatomic) IBOutlet UITextField* phoneNumberTextField;
@property (strong, nonatomic) IBOutlet UILabel* countryCodeLabel;
@property (strong, nonatomic) IBOutlet UILabel* countryNameLabel;
@property (strong, nonatomic) IBOutlet UITextField* challengeTextField;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView* registerActivityIndicator;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView* challengeActivityIndicator;
@property (strong, nonatomic) IBOutlet UIScrollView* scrollView;
@property (strong, nonatomic) IBOutlet UIView* containerView;
@property (strong, nonatomic) IBOutlet UIButton* registerCancelButton;
@property (strong, nonatomic) IBOutlet UIButton* continueToWhisperButton;

@property (strong, nonatomic) IBOutlet UILabel* challengeNumberLabel;
@property (strong, nonatomic) IBOutlet UILabel* voiceChallengeTextLabel;
@property (strong, nonatomic) IBOutlet UIButton* initiateVoiceVerificationButton;

- (IBAction)registerPhoneNumberTapped;
- (IBAction)registerCancelButtonTapped;
- (IBAction)verifyChallengeTapped;
- (IBAction)dismissTapped;
- (IBAction)changeNumberTapped;
- (IBAction)changeCountryCodeTapped;
- (IBAction)initiateVoiceVerificationButtonHandler;

- (instancetype)init;

@end
