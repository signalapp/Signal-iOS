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

static NSString *const SPINNER_CONNECTING_IMAGE_NAME = @"spinner_connecting";
static NSString *const SPINNER_CONNECTING_FLASH_IMAGE_NAME = @"spinner_connecting_flash";
static NSString *const SPINNER_RINGING_IMAGE_NAME = @"spinner_ringing";
static NSString *const SPINNER_ERROR_FLASH_IMAGE_NAME = @"spinner_error";

static NSInteger connectingFlashCounter = 0;


@interface InCallViewController () {
    CallAudioManager *_callAudioManager;
    NSTimer *_connectingFlashTimer;
    NSTimer *_ringingAnimationTimer;
}

@property NSTimer *vibrateTimer;

@end

@implementation InCallViewController

+(InCallViewController*) inCallViewControllerWithCallState:(CallState*)callState
                                 andOptionallyKnownContact:(Contact*)contact {
    require(callState != nil);

    InCallViewController* controller = [InCallViewController new];
    controller->_potentiallyKnownContact = contact;
    controller->_callState = callState;
    controller->_callPushState = PushNotSetState;
    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self showCallState];
    [self setPotentiallyKnownContact:_potentiallyKnownContact];
    [self localizeButtons];
    [self linkActions];
    [[[[Environment getCurrent] contactsManager] getObservableContacts] watchLatestValue:^(NSArray *latestContacts) {
        [self setPotentiallyKnownContact:[[[Environment getCurrent] contactsManager] latestContactForPhoneNumber:_callState.remoteNumber]];
    } onThread:[NSThread mainThread] untilCancelled:nil];
    
    [UIDevice.currentDevice setProximityMonitoringEnabled:YES];
}

-(void)linkActions
{
    [_muteButton addTarget:self action:@selector(muteButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [_speakerButton addTarget:self action:@selector(speakerButtonTapped) forControlEvents:UIControlEventTouchUpInside];
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

-(void) showCallState {
    [self clearDetails];
    [self populateImmediateDetails];
    [self handleIncomingDetails];
}

- (void)startConnectingFlashAnimation {
    if(!_ringingAnimationTimer.isValid){
        _connectingFlashTimer = [NSTimer scheduledTimerWithTimeInterval:CONNECTING_FLASH_DURATION
                                                                 target:self
                                                               selector:@selector(flashConnectingIndicator)
                                                               userInfo:nil
                                                                repeats:YES];
    }
}

- (void)flashConnectingIndicator {
    
    NSString *newImageName;
    
    if (connectingFlashCounter % 2 == 0) {
        newImageName = SPINNER_CONNECTING_IMAGE_NAME;
    } else {
        newImageName = SPINNER_CONNECTING_FLASH_IMAGE_NAME;
    }
    
    [_connectingIndicatorImageView setImage:[UIImage imageNamed:newImageName]];
    connectingFlashCounter++;
}

- (void)startRingingAnimation {
    [self stopConnectingFlashAnimation];
    _ringingAnimationTimer = [NSTimer scheduledTimerWithTimeInterval:RINGING_ROTATION_DURATION
                                                              target:self
                                                            selector:@selector(rotateConnectingIndicator)
                                                            userInfo:nil
                                                             repeats:YES];
    
    if (!_answerButton.hidden) {
        _vibrateTimer = [NSTimer scheduledTimerWithTimeInterval:VIBRATE_TIMER_DURATION
                                                         target:self
                                                       selector:@selector(vibrate)
                                                       userInfo:nil
                                                        repeats:YES];
    }
    
    [_ringingAnimationTimer fire];
}

- (void)vibrate {
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

- (void)rotateConnectingIndicator {
    [_connectingIndicatorImageView setImage:[UIImage imageNamed:SPINNER_RINGING_IMAGE_NAME]];
    [UIView animateWithDuration:RINGING_ROTATION_DURATION delay:0.0 options:UIViewAnimationOptionCurveLinear animations:^{
        _connectingIndicatorImageView.transform = CGAffineTransformRotate(_connectingIndicatorImageView.transform, (float)M_PI_2);
    } completion:nil];
}

- (void)performCallInSessionAnimation {
    [UIView animateWithDuration:0.5f animations:^{
        [_callStateImageContainerView setFrame:CGRectMake(0, _callStateImageContainerView.frame.origin.y, _callStateImageContainerView.frame.size.width, _callStateImageContainerView.frame.size.height)];
    }];
}

- (void)stopRingingAnimation {
    if (_ringingAnimationTimer) {
        [_ringingAnimationTimer invalidate];
    }
    if (_vibrateTimer) {
        [_vibrateTimer invalidate];
    }
}

- (void)stopConnectingFlashAnimation {
    if (_connectingFlashTimer) {
        [_connectingFlashTimer invalidate];
    }
}

- (void)showConnectingError {
    [self stopRingingAnimation];
    [self stopConnectingFlashAnimation];
    [_connectingIndicatorImageView setImage:[UIImage imageNamed:SPINNER_ERROR_FLASH_IMAGE_NAME]];
}

- (void)localizeButtons {
    [_endButton setTitle:END_CALL_BUTTON_TITLE forState:UIControlStateNormal];
    [_answerButton setTitle:ANSWER_CALL_BUTTON_TITLE forState:UIControlStateNormal];
    [_rejectButton setTitle:REJECT_CALL_BUTTON_TITLE forState:UIControlStateNormal];
}

- (void)setPotentiallyKnownContact:(Contact *)potentiallyKnownContact {
    _potentiallyKnownContact = potentiallyKnownContact;
    
    if (_potentiallyKnownContact) {

        if (_potentiallyKnownContact.image) {
            [UIUtil applyRoundedBorderToImageView:&_contactImageView];
        }
        
        _nameLabel.text = _potentiallyKnownContact.fullName;
    } else {
        _nameLabel.text = UNKNOWN_CONTACT_NAME;
    }
}

-(void) clearDetails {
    _callStatusLabel.text				= @"";
    _nameLabel.text						= @"";
    _phoneNumberLabel.text				= @"";
    _authenicationStringLabel.text		= @"";
    _contactImageView.image				= nil;
    _authenicationStringLabel.hidden	= YES;
    [self displayAcceptRejectButtons:NO];
}

-(void) populateImmediateDetails {
    _phoneNumberLabel.text = _callState.remoteNumber.localizedDescriptionForUser;

    if (_potentiallyKnownContact) {
        _nameLabel.text = _potentiallyKnownContact.fullName;
        if (_potentiallyKnownContact.image) {
            _contactImageView.image = _potentiallyKnownContact.image;
        }
    }
}
-(void) handleIncomingDetails {
    [_callState.futureShortAuthenticationString thenDo:^(NSString* sas) {
        _authenicationStringLabel.textColor = [UIColor colorWithRed:0.f/255.f green:12.f/255.f blue:255.f/255.f alpha:1.0f];
        _authenicationStringLabel.hidden = NO;
        _authenicationStringLabel.text = sas;
        [self performCallInSessionAnimation];
    }];

    [[_callState observableProgress] watchLatestValue:^(CallProgress* latestProgress) {
        [self onCallProgressed:latestProgress];
    } onThread:NSThread.mainThread untilCancelled:nil];
}

-(void) onCallProgressed:(CallProgress*)latestProgress {
    BOOL showAcceptRejectButtons = !_callState.initiatedLocally && [latestProgress type] <= CallProgressType_Ringing;
    [self displayAcceptRejectButtons:showAcceptRejectButtons];
    [AppAudioManager.sharedInstance respondToProgressChange:[latestProgress type]
                                    forLocallyInitiatedCall:_callState.initiatedLocally];
    
    if ([latestProgress type] == CallProgressType_Ringing) {
        [self startRingingAnimation];
    }
    
    if ([latestProgress type] == CallProgressType_Terminated) {
        [_callState.futureTermination thenDo:^(CallTermination* termination) {
            [self onCallEnded:termination];
            [AppAudioManager.sharedInstance respondToTerminationType:[termination type]];
        }];
    } else {
        _callStatusLabel.text = latestProgress.localizedDescriptionForUser;
    }
}

-(void) onCallEnded:(CallTermination*)termination {
    [self updateViewForTermination:termination];
    [Environment.phoneManager hangupOrDenyCall];
    
    [self dismissViewWithOptionalDelay: [termination type] != CallTerminationType_ReplacedByNext ];
}

- (void)endCallTapped {
    [Environment.phoneManager hangupOrDenyCall];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)muteButtonTapped {
	_muteButton.selected = [Environment.phoneManager toggleMute];
    
    if (_muteButton.isSelected)
    {
        _muteLabel.text = @"Mute On";
    } else {
        _muteLabel.text = @"Mute Off";
    }
}

- (void)speakerButtonTapped {
    _speakerButton.selected = [AppAudioManager.sharedInstance toggleSpeakerPhone];
    
    if (_speakerButton.isSelected)
    {
        _speakerLabel.text = @"Speaker On";
    } else {
        _speakerLabel.text = @"Speaker Off";
    }
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

-(void) updateViewForTermination:(CallTermination*) termination{
    NSString* message = termination.localizedDescriptionForUser;
    
    if ([termination type] == CallTerminationType_ServerMessage) {
        CallFailedServerMessage* serverMessage = [termination messageInfo];
        message = [message stringByAppendingString:[serverMessage text]];
    }
    
    _callStatusLabel.textColor = [UIColor ows_redColor];
    
    [self showConnectingError];
    _callStatusLabel.text = message;
}

-(void) dismissViewWithOptionalDelay:(BOOL) useDelay {
    [UIDevice.currentDevice setProximityMonitoringEnabled:NO];
    if(useDelay && UIApplicationStateActive == [UIApplication.sharedApplication applicationState]){
        [self dismissViewControllerAfterDelay:END_CALL_CLEANUP_DELAY];
    }else{
        [self dismissViewControllerAnimated:NO completion:nil];
    }
}

-(void) dismissViewControllerAfterDelay:(int) delay {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay), dispatch_get_main_queue(), ^{
        [self dismissViewControllerAnimated:YES completion:nil];
    });
}

-(void) displayAcceptRejectButtons:(BOOL) enable{
    
    _answerButton.hidden = !enable;
    _rejectButton.hidden = !enable;
    _endButton.hidden    = enable;
    
    _answerLabel.hidden  = !enable;
    _rejectLabel.hidden  = !enable;
    _endLabel.hidden     = enable;
    
    if (_vibrateTimer && enable == false) {
        [_vibrateTimer invalidate];
    }
}

@end
