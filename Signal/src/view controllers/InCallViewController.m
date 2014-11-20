#import "AppAudioManager.h"
#import "CallFailedServerMessage.h"
#import "InCallViewController.h"
#import "LocalizableText.h"
#import "RecentCallManager.h"
#import "Util.h"
#import "CallAudioManager.h"
#import "PhoneManager.h"

#import <AudioToolbox/AudioServices.h>

#define BUTTON_BORDER_WIDTH 1.0f
#define CONTACT_IMAGE_BORDER_WIDTH 2.0f
#define RINGING_ROTATION_DURATION 0.375f
#define VIBRATE_TIMER_DURATION 1.6
#define CONNECTING_FLASH_DURATION 0.5f
#define END_CALL_CLEANUP_DELAY (int)(3.1f * NSEC_PER_SEC)

static NSString* const SPINNER_CONNECTING_IMAGE_NAME = @"spinner_connecting";
static NSString* const SPINNER_CONNECTING_FLASH_IMAGE_NAME = @"spinner_connecting_flash";
static NSString* const SPINNER_RINGING_IMAGE_NAME = @"spinner_ringing";
static NSString* const SPINNER_ERROR_FLASH_IMAGE_NAME = @"spinner_error";

static NSInteger connectingFlashCounter = 0;

@interface InCallViewController ()

@property (strong, nonatomic) CallAudioManager* callAudioManager;
@property (strong, nonatomic) NSTimer* connectingFlashTimer;
@property (strong, nonatomic) NSTimer* ringingAnimationTimer;
@property (strong, nonatomic) NSTimer* vibrateTimer;

@property (strong, readwrite, nonatomic) CallState* callState;
@property (strong, readwrite, nonatomic) Contact* potentiallyKnownContact;
@property (readwrite, nonatomic) PushAcceptState callPushState;

@end

@implementation InCallViewController

@synthesize contactImageView = _contactImageView;

- (instancetype)initWithCallState:(CallState*)callState
        andOptionallyKnownContact:(Contact*)contact {
    self = [super init];
	
    if (self) {
        require(callState != nil);
        
        self.potentiallyKnownContact = contact;
        self.callState = callState;
        self.callPushState = PushAcceptStateNotSet;
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self showCallState];
    [self setupButtonBorders];
    [self localizeButtons];
    [UIDevice.currentDevice setProximityMonitoringEnabled:YES];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self startConnectingFlashAnimation];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopRingingAnimation];
    [self stopConnectingFlashAnimation];
    [AppAudioManager.sharedInstance cancellAllAudio];
}

- (void)dealloc {
    [UIDevice.currentDevice setProximityMonitoringEnabled:NO];
}

- (void)showCallState {
    [self clearDetails];
    [self populateImmediateDetails];
    [self handleIncomingDetails];
}

- (void)startConnectingFlashAnimation {
    if (!self.ringingAnimationTimer.isValid) {
        self.connectingFlashTimer = [NSTimer scheduledTimerWithTimeInterval:CONNECTING_FLASH_DURATION
                                                                     target:self
                                                                   selector:@selector(flashConnectingIndicator)
                                                                   userInfo:nil
                                                                    repeats:YES];
    }
}

- (void)flashConnectingIndicator {
    
    NSString* newImageName;
    
    if (connectingFlashCounter % 2 == 0) {
        newImageName = SPINNER_CONNECTING_IMAGE_NAME;
    } else {
        newImageName = SPINNER_CONNECTING_FLASH_IMAGE_NAME;
    }
    
    [self.connectingIndicatorImageView setImage:[UIImage imageNamed:newImageName]];
    connectingFlashCounter++;
}

- (void)startRingingAnimation {
    [self stopConnectingFlashAnimation];
    self.ringingAnimationTimer = [NSTimer scheduledTimerWithTimeInterval:RINGING_ROTATION_DURATION
                                                                  target:self
                                                                selector:@selector(rotateConnectingIndicator)
                                                                userInfo:nil
                                                                 repeats:YES];
    
    if (!self.answerButton.hidden) {
        self.vibrateTimer = [NSTimer scheduledTimerWithTimeInterval:VIBRATE_TIMER_DURATION
                                                             target:self
                                                           selector:@selector(vibrate)
                                                           userInfo:nil
                                                            repeats:YES];
    }
    
    [self.ringingAnimationTimer fire];
}

- (void)vibrate {
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

- (void)rotateConnectingIndicator {
    [self.connectingIndicatorImageView setImage:[UIImage imageNamed:SPINNER_RINGING_IMAGE_NAME]];
    [UIView animateWithDuration:RINGING_ROTATION_DURATION delay:0.0 options:UIViewAnimationOptionCurveLinear animations:^{
        self.connectingIndicatorImageView.transform = CGAffineTransformRotate(self.connectingIndicatorImageView.transform, (float)M_PI_2);
    } completion:nil];
}

- (void)performCallInSessionAnimation {
    [UIView animateWithDuration:0.5f animations:^{
        [self.callStateImageContainerView setFrame:CGRectMake(0,
                                                              self.callStateImageContainerView.frame.origin.y,
                                                              self.callStateImageContainerView.frame.size.width,
                                                              self.callStateImageContainerView.frame.size.height)];
    }];
}

- (void)stopRingingAnimation {
    if (self.ringingAnimationTimer) {
        [self.ringingAnimationTimer invalidate];
    }
    if (self.vibrateTimer) {
        [self.vibrateTimer invalidate];
    }
}

- (void)stopConnectingFlashAnimation {
    if (self.connectingFlashTimer) {
        [self.connectingFlashTimer invalidate];
    }
}

- (void)showConnectingError {
    [self stopRingingAnimation];
    [self stopConnectingFlashAnimation];
    [self.connectingIndicatorImageView setImage:[UIImage imageNamed:SPINNER_ERROR_FLASH_IMAGE_NAME]];
}

- (void)localizeButtons {
    [self.endButton setTitle:END_CALL_BUTTON_TITLE forState:UIControlStateNormal];
    [self.answerButton setTitle:ANSWER_CALL_BUTTON_TITLE forState:UIControlStateNormal];
    [self.rejectButton setTitle:REJECT_CALL_BUTTON_TITLE forState:UIControlStateNormal];
}

- (void)setupButtonBorders {
    self.muteButton.layer.borderColor		= [UIUtil.blueColor CGColor];
    self.speakerButton.layer.borderColor	= [UIUtil.blueColor CGColor];
    self.muteButton.layer.borderWidth		= BUTTON_BORDER_WIDTH;
    self.speakerButton.layer.borderWidth	= BUTTON_BORDER_WIDTH;

    if (self.potentiallyKnownContact) {

        if (self.potentiallyKnownContact.image) {
            [UIUtil applyRoundedBorderToImageView:&_contactImageView];
        }
        
        self.nameLabel.text = self.potentiallyKnownContact.fullName;
    } else {
        self.nameLabel.text = UNKNOWN_CONTACT_NAME;
    }
}

- (void)clearDetails {
    self.callStatusLabel.text				= @"";
    self.nameLabel.text						= @"";
    self.phoneNumberLabel.text				= @"";
    self.authenicationStringLabel.text		= @"";
    self.contactImageView.image				= nil;
    self.authenicationStringLabel.hidden	= YES;
    [self displayAcceptRejectButtons:NO];
}

- (void)populateImmediateDetails {
    self.phoneNumberLabel.text = self.callState.remoteNumber.localizedDescriptionForUser;

    if (self.potentiallyKnownContact) {
        self.nameLabel.text = self.potentiallyKnownContact.fullName;
        if (self.potentiallyKnownContact.image) {
            self.contactImageView.image = self.potentiallyKnownContact.image;
        }
    }
}

- (void)handleIncomingDetails {
    [self.callState.futureShortAuthenticationString thenDo:^(NSString* sas) {
        self.authenicationStringLabel.hidden = NO;
        self.authenicationStringLabel.text = sas;
        [self performCallInSessionAnimation];
    }];

    [[self.callState observableProgress] watchLatestValue:^(CallProgress* latestProgress) {
        [self onCallProgressed:latestProgress];
    } onThread:NSThread.mainThread untilCancelled:nil];
}

- (void)onCallProgressed:(CallProgress*)latestProgress {
    BOOL showAcceptRejectButtons = !self.callState.initiatedLocally && [latestProgress type] <= CallProgressTypeRinging;
    [self displayAcceptRejectButtons:showAcceptRejectButtons];
    [AppAudioManager.sharedInstance respondToProgressChange:[latestProgress type]
                                      forLocallyInitiatedCall:self.callState.initiatedLocally];
    
    if (latestProgress.type == CallProgressTypeRinging) {
        [self startRingingAnimation];
    }
    
    if (latestProgress.type == CallProgressTypeTerminated) {
        [self.callState.futureTermination thenDo:^(CallTermination* termination) {
            [self onCallEnded:termination];
            [AppAudioManager.sharedInstance respondToTerminationType:[termination type]];
        }];
    } else {
        self.callStatusLabel.text = latestProgress.localizedDescriptionForUser;
    }
}

- (void)onCallEnded:(CallTermination*)termination {
    [self updateViewForTermination:termination];
    [Environment.phoneManager hangupOrDenyCall];
    
    [self dismissViewWithOptionalDelay: [termination type] != CallTerminationTypeReplacedByNext ];
}

- (void)endCallTapped {
    [Environment.phoneManager hangupOrDenyCall];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)muteButtonTapped {
	self.muteButton.selected = [Environment.phoneManager toggleMute];
}

- (void)speakerButtonTapped {
    self.speakerButton.selected = [AppAudioManager.sharedInstance toggleSpeakerPhone];
}

- (void)answerButtonTapped {
    [self displayAcceptRejectButtons:NO];
    [Environment.phoneManager answerCall];
}

- (void)rejectButtonTapped {
    [self displayAcceptRejectButtons:NO];
    [Environment.phoneManager hangupOrDenyCall];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)updateViewForTermination:(CallTermination*)termination {
    NSString* message = [termination localizedDescriptionForUser];
    
    if (termination.type == CallTerminationTypeServerMessage) {
        CallFailedServerMessage* serverMessage = termination.messageInfo;
        message = [message stringByAppendingString:serverMessage.text];
    }
    
    self.endButton.backgroundColor = UIColor.grayColor;
    self.callStatusLabel.textColor = UIColor.redColor;
    
    [self showConnectingError];
    self.callStatusLabel.text = message;
}

- (void)dismissViewWithOptionalDelay:(BOOL)useDelay {
    if (useDelay && UIApplicationStateActive == [UIApplication.sharedApplication applicationState]) {
        [self dismissViewControllerAfterDelay:END_CALL_CLEANUP_DELAY];
    } else {
        [self dismissViewControllerAnimated:NO completion:nil];
    }
}

- (void)dismissViewControllerAfterDelay:(int)delay {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay), dispatch_get_main_queue(), ^{
        [self dismissViewControllerAnimated:YES completion:nil];
    });
}

- (void)displayAcceptRejectButtons:(BOOL)enable {
    self.answerButton.hidden = !enable;
    self.rejectButton.hidden = !enable;
    self.endButton.hidden = enable;
    if (self.vibrateTimer && enable == false) {
        [self.vibrateTimer invalidate];
    }
}

@end
