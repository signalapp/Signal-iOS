#import "AppAudioManager.h"
#import "CallFailedServerMessage.h"
#import "InCallViewController.h"
#import "LocalizableText.h"
#import "RecentCallManager.h"
#import "Util.h"
#import "CallAudioManager.h"
#import "PhoneManager.h"

#import <MediaPlayer/MPMusicPlayerController.h>

#define BUTTON_BORDER_WIDTH 1.0f
#define CONTACT_IMAGE_BORDER_WIDTH 2.0f
#define RINGING_ROTATION_DURATION 0.375f
#define CONNECTING_FLASH_DURATION 0.5f
#define END_CALL_CLEANUP_DELAY (int)(3.1f * NSEC_PER_SEC)

static NSString *const SPINNER_CONNECTING_IMAGE_NAME = @"spinner_connecting";
static NSString *const SPINNER_CONNECTING_FLASH_IMAGE_NAME = @"spinner_connecting_flash";
static NSString *const SPINNER_RINGING_IMAGE_NAME = @"spinner_ringing";
static NSString *const SPINNER_ERROR_FLASH_IMAGE_NAME = @"spinner_error";

static NSInteger connectingFlashCounter = 0;


@interface InCallViewController () {
    BOOL _isMusicPaused;
    CallAudioManager *_callAudioManager;
    NSTimer *_connectingFlashTimer;
    NSTimer *_ringingAnimationTimer;
}

@end

@implementation InCallViewController

+(InCallViewController*) inCallViewControllerWithCallState:(CallState*)callState
                                 andOptionallyKnownContact:(Contact*)contact {
    require(callState != nil);

    InCallViewController* controller = [InCallViewController new];
    controller->_potentiallyKnownContact = contact;
    controller->_callState = callState;
    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self showCallState];
    [self pauseMusicIfPlaying];
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

-(void) showCallState {
    [self clearDetails];
    [self populateImmediateDetails];
    [self handleIncomingDetails];
}

- (void)pauseMusicIfPlaying {
    if ([[MPMusicPlayerController iPodMusicPlayer] playbackState] == MPMusicPlaybackStatePlaying) {
        _isMusicPaused = YES;
        [[MPMusicPlayerController iPodMusicPlayer] pause];
    }
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
    [_ringingAnimationTimer fire];
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

- (void)setupButtonBorders {
    _muteButton.layer.borderColor		= [UIUtil blueColor].CGColor;
    _speakerButton.layer.borderColor	= [UIUtil blueColor].CGColor;
    _muteButton.layer.borderWidth		= BUTTON_BORDER_WIDTH;
    _speakerButton.layer.borderWidth	= BUTTON_BORDER_WIDTH;

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
    
    if (_isMusicPaused) {
        [[MPMusicPlayerController iPodMusicPlayer] play];
    }
}

- (void)endCallTapped {
    [Environment.phoneManager hangupOrDenyCall];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)muteButtonTapped {
	_muteButton.selected = [Environment.phoneManager toggleMute];
}

- (void)speakerButtonTapped {
    _speakerButton.selected = [AppAudioManager.sharedInstance toggleSpeakerPhone];
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
    
    _endButton.backgroundColor = [UIColor grayColor];
    _callStatusLabel.textColor = [UIColor redColor];
    
    [self showConnectingError];
    _callStatusLabel.text = message;
}

-(void) dismissViewWithOptionalDelay:(BOOL) useDelay {
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
    _endButton.hidden = enable;
    
}







@end
