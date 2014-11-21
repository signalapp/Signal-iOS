#import <UIKit/UIKit.h>

#import "Contact.h"
#import "PhoneManager.h"
#import "PhoneNumber.h"
#import "PhoneNumberDirectoryFilterManager.h"

@interface InCallViewController : UIViewController

@property (nonatomic, strong) IBOutlet UILabel *nameLabel;
@property (nonatomic, strong) IBOutlet UILabel *phoneNumberLabel;
@property (nonatomic, strong) IBOutlet UILabel *callStatusLabel;
@property (nonatomic, strong) IBOutlet UIImageView *contactImageView;
@property (nonatomic, strong) IBOutlet UIImageView *connectingIndicatorImageView;
@property (nonatomic, strong) IBOutlet UILabel *authenicationStringLabel;
@property (nonatomic, strong) IBOutlet UIView *verticalSpinnerAlignmentView;
@property (nonatomic, strong) IBOutlet UIView *callStateImageContainerView;

@property (nonatomic, strong) IBOutlet UIButton *muteButton;
@property (nonatomic, strong) IBOutlet UILabel* muteLabel;
@property (nonatomic, strong) IBOutlet UIButton *speakerButton;
@property (nonatomic, strong) IBOutlet UILabel* speakerLabel;

@property (nonatomic, strong) IBOutlet UIButton *answerButton;
@property (nonatomic, strong) IBOutlet UILabel  *answerLabel;
@property (nonatomic, strong) IBOutlet UIButton *rejectButton;
@property (nonatomic, strong) IBOutlet UILabel  *rejectLabel;

@property (nonatomic, strong) IBOutlet UIButton *endButton;
@property (nonatomic, strong) IBOutlet UILabel  *endLabel;

@property (nonatomic, readonly) CallState *callState;
@property (nonatomic, readonly) Contact *potentiallyKnownContact;

typedef NS_ENUM(NSInteger, PushAcceptState){
    PushDidAcceptState,
    PushDidDeclineState,
    PushNotSetState
};

@property (nonatomic, readonly) PushAcceptState callPushState;

+(InCallViewController*) inCallViewControllerWithCallState:(CallState*)callState
                                 andOptionallyKnownContact:(Contact*)contact;

- (IBAction)endCallTapped;
- (IBAction)muteButtonTapped;
- (IBAction)speakerButtonTapped;

- (IBAction)answerButtonTapped;
- (IBAction)rejectButtonTapped;


@end
