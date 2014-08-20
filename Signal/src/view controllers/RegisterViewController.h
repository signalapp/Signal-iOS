#import <UIKit/UIKit.h>

#import "CollapsingFutures.h"
#import "CountryCodeViewController.h"

@interface RegisterViewController : UIViewController <CountryCodeViewControllerDelegate, UITextFieldDelegate> {
@private TOCFutureSource* registered;
@private TOCFutureSource* futureChallengeAcceptedSource;
@private TOCCancelTokenSource* life;
}

@property (nonatomic, strong) IBOutlet UIButton *registerButton;
@property (nonatomic, strong) IBOutlet UIButton *challengeButton;
@property (nonatomic, strong) IBOutlet UITextField *phoneNumberTextField;
@property (nonatomic, strong) IBOutlet UILabel *countryCodeLabel;
@property (nonatomic, strong) IBOutlet UILabel *countryNameLabel;
@property (nonatomic, strong) IBOutlet UITextField *challengeTextField;
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

+ (RegisterViewController*)registerViewController;

@end
