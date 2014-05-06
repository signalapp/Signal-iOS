#import <UIKit/UIKit.h>

#import "CancelTokenSource.h"
#import "CountryCodeViewController.h"
#import "FutureSource.h"

@interface RegisterViewController : UIViewController <CountryCodeViewControllerDelegate, UITextFieldDelegate> {
@private Future* futureApnId;
@private FutureSource* registered;
@private FutureSource* futureChallengeAcceptedSource;
@private CancelTokenSource* life;
}

@property (nonatomic, strong) IBOutlet UIButton *registerButton;
@property (nonatomic, strong) IBOutlet UIButton *challengeButton;
@property (nonatomic, strong) IBOutlet UITextField *phoneNumberTextField;
@property (nonatomic, strong) IBOutlet UILabel *countryCodeLabel;
@property (nonatomic, strong) IBOutlet UILabel *countryNameLabel;
@property (nonatomic, strong) IBOutlet UITextField *challengeTextField;
@property (nonatomic, strong) IBOutlet UILabel *registerErrorLabel;
@property (nonatomic, strong) IBOutlet UILabel *challengeErrorLabel;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *registerActivityIndicator;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *challengeActivityIndicator;
@property (nonatomic, strong) IBOutlet UIScrollView *scrollView;
@property (nonatomic, strong) IBOutlet UIView *containerView;
@property (nonatomic, strong) IBOutlet UIButton *registerCancelButton;
@property (nonatomic, strong) IBOutlet UIButton *continueToWhisperButton;

@property (nonatomic, strong) IBOutlet UILabel *challengeNumberLabel;
@property (nonatomic, strong) IBOutlet UILabel *voiceChallengeTextLabel;
@property (nonatomic, strong) IBOutlet UIButton *initiateVoiceVerificationButton;

- (IBAction)registerPhoneNumberTapped;
- (IBAction)registerCancelButtonTapped;
- (IBAction)verifyChallengeTapped;
- (IBAction)dismissTapped;
- (IBAction)changeNumberTapped;
- (IBAction)changeCountryCodeTapped;
- (IBAction)initiateVoiceVerificationButtonHandler;

+ (RegisterViewController*)registerViewControllerForApn:(Future *)apnId;

@end
