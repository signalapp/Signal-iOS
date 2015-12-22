#import <UIKit/UIKit.h>

#import "Contact.h"
#import "PhoneManager.h"
#import "PhoneNumber.h"

#define PICK_UP_NOTIFICATION @"RedPhoneCallPickUpNotification"
#define HANG_UP_NOTIFICATION @"RedPhoneCallHangUpNotification"


@interface InCallViewController : UIViewController

@property (nonatomic, strong) IBOutlet UIView *conversationContactView;
@property (nonatomic, strong) IBOutlet UILabel *nameLabel;
@property (nonatomic, strong) IBOutlet UILabel *callStatusLabel;
@property (nonatomic, strong) IBOutlet UIImageView *contactImageView;


@property (nonatomic, strong) IBOutlet UIView *safeWordsView;
@property (nonatomic, strong) IBOutlet UILabel *authenicationStringLabel;
@property (nonatomic, strong) IBOutlet UILabel *explainAuthenticationStringLabel;


@property (nonatomic, strong) IBOutlet UIView *activeOrIncomingButtonsView;
@property (nonatomic, strong) IBOutlet UIButton *muteButton;
@property (nonatomic, strong) IBOutlet UIButton *speakerButton;

@property (nonatomic, strong) IBOutlet UIView *activeCallButtonsView;
@property (nonatomic, strong) IBOutlet UIButton *endButton;


@property (nonatomic, strong) IBOutlet UIView *incomingCallButtonsView;
@property (nonatomic, strong) IBOutlet UIButton *rejectButton;
@property (nonatomic, strong) IBOutlet UIButton *answerButton;

@property IBOutlet UIView *containerView;

@property (nonatomic, readonly) CallState *callState;
@property (nonatomic, readonly) Contact *potentiallyKnownContact;

typedef NS_ENUM(NSInteger, PushAcceptState) { PushDidAcceptState, PushDidDeclineState, PushNotSetState };

@property (nonatomic, readonly) PushAcceptState callPushState;

- (void)configureWithLatestCall:(CallState *)callState;

- (IBAction)endCallTapped;
- (IBAction)muteButtonTapped;
- (IBAction)speakerButtonTapped;

- (IBAction)answerButtonTapped;
- (IBAction)rejectButtonTapped;


@end
