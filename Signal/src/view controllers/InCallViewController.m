#import "AppAudioManager.h"
#import "CallFailedServerMessage.h"
#import "InCallViewController.h"
#import "LocalizableText.h"
#import "RecentCallManager.h"

#define BUTTON_BORDER_WIDTH 1.0f
#define CONTACT_IMAGE_BORDER_WIDTH 2.0f
#define RINGING_ROTATION_DURATION 0.375f
#define VIBRATE_TIMER_DURATION 1.6
#define CONNECTING_FLASH_DURATION 0.5f
#define END_CALL_CLEANUP_DELAY (int)(3.1f * NSEC_PER_SEC)


@interface InCallViewController () {
    CallAudioManager *_callAudioManager;
    NSTimer *_connectingFlashTimer;
    NSTimer *_ringingAnimationTimer;
}

@property NSTimer *vibrateTimer;

@end

@implementation InCallViewController


- (void)configureWithLatestCall:(CallState *)callState {
    _potentiallyKnownContact = callState.potentiallySpecifiedContact;
    _callState               = callState;
    _callPushState           = PushNotSetState;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self showCallState];
    [self setPotentiallyKnownContact:_potentiallyKnownContact];
    [self localizeButtons];
    [self linkActions];
    [[[[Environment getCurrent] contactsManager] getObservableContacts] watchLatestValue:^(NSArray *latestContacts) {
      [self setPotentiallyKnownContact:[[[Environment getCurrent] contactsManager]
                                           latestContactForPhoneNumber:_callState.remoteNumber]];
    }
                                                                                onThread:[NSThread mainThread]
                                                                          untilCancelled:nil];
}

- (void)linkActions {
    [_muteButton addTarget:self action:@selector(muteButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [_speakerButton addTarget:self action:@selector(speakerButtonTapped) forControlEvents:UIControlEventTouchUpInside];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [UIDevice.currentDevice setProximityMonitoringEnabled:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopRingingAnimation];
    [self stopConnectingFlashAnimation];
    [AppAudioManager.sharedInstance cancellAllAudio];
    [UIDevice.currentDevice setProximityMonitoringEnabled:NO];
}

- (void)showCallState {
    [self clearDetails];
    [self populateImmediateDetails];
    [self handleIncomingDetails];
}

- (void)startRingingAnimation {
    [self stopConnectingFlashAnimation];

    if (!_incomingCallButtonsView.hidden) {
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
        _nameLabel.text = _callState.remoteNumber.toE164;
    }
}

- (void)clearDetails {
    _callStatusLabel.text                  = @"";
    _nameLabel.text                        = @"";
    _authenicationStringLabel.text         = @"";
    _explainAuthenticationStringLabel.text = @"";
    _contactImageView.image                = nil;
    _safeWordsView.hidden                  = YES;
    _muteButton.hidden                     = YES;
    _speakerButton.hidden                  = YES;
    [self displayAcceptRejectButtons:NO];
}

- (void)populateImmediateDetails {
    if (_potentiallyKnownContact) {
        _nameLabel.text = _potentiallyKnownContact.fullName;
        if (_potentiallyKnownContact.image) {
            _contactImageView.image = _potentiallyKnownContact.image;
        }
    }
}
- (void)handleIncomingDetails {
    [_callState.futureShortAuthenticationString thenDo:^(NSString *sas) {
      _authenicationStringLabel.textColor = [UIColor ows_materialBlueColor];
      _safeWordsView.hidden               = NO;
      _muteButton.hidden                  = NO;
      _speakerButton.hidden               = NO;
      _authenicationStringLabel.text      = sas;
    }];

    [[_callState observableProgress] watchLatestValue:^(CallProgress *latestProgress) {
      [self onCallProgressed:latestProgress];
    }
                                             onThread:NSThread.mainThread
                                       untilCancelled:nil];
}

- (void)onCallProgressed:(CallProgress *)latestProgress {
    BOOL showAcceptRejectButtons = !_callState.initiatedLocally && [latestProgress type] <= CallProgressType_Ringing;
    [self displayAcceptRejectButtons:showAcceptRejectButtons];
    [AppAudioManager.sharedInstance respondToProgressChange:[latestProgress type]
                                    forLocallyInitiatedCall:_callState.initiatedLocally];

    if ([latestProgress type] == CallProgressType_Ringing) {
        [self startRingingAnimation];
    }

    if ([latestProgress type] == CallProgressType_Terminated) {
        [_callState.futureTermination thenDo:^(CallTermination *termination) {
          [self onCallEnded:termination];
          [AppAudioManager.sharedInstance respondToTerminationType:[termination type]];
        }];
    } else {
        _callStatusLabel.text = latestProgress.localizedDescriptionForUser;
    }
}

- (void)onCallEnded:(CallTermination *)termination {
    [self updateViewForTermination:termination];
    [Environment.phoneManager hangupOrDenyCall];

    [self dismissViewWithOptionalDelay:[termination type] != CallTerminationType_ReplacedByNext];
}

- (void)endCallTapped {
    [Environment.phoneManager hangupOrDenyCall];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)muteButtonTapped {
    [_muteButton setSelected:[Environment.phoneManager toggleMute]];
}

- (void)speakerButtonTapped {
    [_speakerButton setSelected:[AppAudioManager.sharedInstance toggleSpeakerPhone]];
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

- (void)updateViewForTermination:(CallTermination *)termination {
    NSString *message = termination.localizedDescriptionForUser;

    if ([termination type] == CallTerminationType_ServerMessage) {
        CallFailedServerMessage *serverMessage = [termination messageInfo];
        message                                = [message stringByAppendingString:[serverMessage text]];
    }

    _callStatusLabel.textColor = [UIColor ows_redColor];

    [self showConnectingError];
    _callStatusLabel.text = message;
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
    _incomingCallButtonsView.hidden = !enable;
    _activeCallButtonsView.hidden   = enable;

    if (_vibrateTimer && enable == false) {
        [_vibrateTimer invalidate];
    }
}

@end
