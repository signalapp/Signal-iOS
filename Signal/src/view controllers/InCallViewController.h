#import <UIKit/UIKit.h>

#import "Contact.h"
#import "PhoneManager.h"
#import "PhoneNumber.h"
#import "PhoneNumberDirectoryFilterManager.h"

typedef NS_ENUM(NSInteger, PushAcceptState) {
    PushAcceptStateDidAccept,
    PushAcceptStateDidDecline,
    PushAcceptStateNotSet
};

@interface InCallViewController : UIViewController

@property (strong, nonatomic) IBOutlet UILabel* nameLabel;
@property (strong, nonatomic) IBOutlet UILabel* phoneNumberLabel;
@property (strong, nonatomic) IBOutlet UILabel* callStatusLabel;
@property (strong, nonatomic) IBOutlet UIImageView* contactImageView;
@property (strong, nonatomic) IBOutlet UIImageView* connectingIndicatorImageView;
@property (strong, nonatomic) IBOutlet UILabel* authenicationStringLabel;
@property (strong, nonatomic) IBOutlet UIView* verticalSpinnerAlignmentView;
@property (strong, nonatomic) IBOutlet UIView* callStateImageContainerView;
@property (strong, nonatomic) IBOutlet UIButton* muteButton;
@property (strong, nonatomic) IBOutlet UIButton* speakerButton;
@property (strong, nonatomic) IBOutlet UIButton* answerButton;
@property (strong, nonatomic) IBOutlet UIButton* rejectButton;
@property (strong, nonatomic) IBOutlet UIButton* endButton;

@property (strong, readonly, nonatomic) CallState* callState;
@property (strong, readonly, nonatomic) Contact* potentiallyKnownContact;
@property (readonly, nonatomic) PushAcceptState callPushState;

- (instancetype)initWithCallState:(CallState*)callState
        andOptionallyKnownContact:(Contact*)contact;

- (IBAction)endCallTapped;
- (IBAction)muteButtonTapped;
- (IBAction)speakerButtonTapped;

- (IBAction)answerButtonTapped;
- (IBAction)rejectButtonTapped;


@end
