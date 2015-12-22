#import "AppAudioManager.h"

#import "AudioRouter.h"
#import "SoundBoard.h"


#define DEFAULT_CATEGORY AVAudioSessionCategorySoloAmbient
#define RECORDING_CATEGORY AVAudioSessionCategoryPlayAndRecord


AppAudioManager *sharedAppAudioManager;

@interface AppAudioManager () <UIAlertViewDelegate> {
    enum AudioProfile _audioProfile;
    BOOL isSpeakerphoneActive;
}
@property (retain) SoundPlayer *soundPlayer;
@end


@implementation AppAudioManager

+ (AppAudioManager *)sharedInstance {
    @synchronized(self) {
        if (nil == sharedAppAudioManager) {
            sharedAppAudioManager             = [AppAudioManager new];
            sharedAppAudioManager.soundPlayer = [SoundPlayer new];
            [[sharedAppAudioManager soundPlayer] setDelegate:sharedAppAudioManager];
        }
    }
    return sharedAppAudioManager;
}

#pragma mark AudioState Management

- (void)setAudioProfile:(enum AudioProfile)profile {
    [self updateAudioRouter];
    _audioProfile = profile;
}

- (void)updateAudioRouter {
    if (isSpeakerphoneActive) {
        [AudioRouter routeAllAudioToExternalSpeaker];
    } else {
        switch (_audioProfile) {
            case AudioProfile_Default:
                [AudioRouter routeAllAudioToInteralSpeaker];
                break;
            case AudioProfile_ExternalSpeaker:
                [AudioRouter routeAllAudioToExternalSpeaker];
                break;
            default:
                DDLogError(@"Unhandled AudioProfile");
        }
    }
}


- (void)overrideAudioProfile {
    isSpeakerphoneActive = YES;
    [self updateAudioRouter];
}

- (void)resetOverride {
    isSpeakerphoneActive = NO;
    [self updateAudioRouter];
}

- (enum AudioProfile)getCurrentAudioProfile {
    return (isSpeakerphoneActive) ? AudioProfile_ExternalSpeaker : _audioProfile;
}

#pragma mark AudioControl;
- (void)respondToProgressChange:(enum CallProgressType)progressType forLocallyInitiatedCall:(BOOL)initiatedLocally {
    switch (progressType) {
        case CallProgressType_Connecting:
            [sharedAppAudioManager setAudioEnabled:YES];
        case CallProgressType_Ringing:
            (initiatedLocally) ? [self handleOutboundRing] : [self handleInboundRing];
            break;
        case CallProgressType_Terminated:
            break;
        case CallProgressType_Securing:
            [self handleSecuring];
            break;
        case CallProgressType_Talking:
            [self handleCallEstablished];
            break;
    }
}

- (void)respondToTerminationType:(enum CallTerminationType)terminationType {
    if (terminationType == CallTerminationType_ResponderIsBusy) {
        [_soundPlayer playSound:[SoundBoard instanceOfBusySound]];
    } else if ([self shouldErrorSoundBePlayedForCallTerminationType:terminationType]) {
        [_soundPlayer playSound:[SoundBoard instanceOfErrorAlert]];
    } else {
        [_soundPlayer playSound:[SoundBoard instanceOfAlert]];
    }
}

- (BOOL)shouldErrorSoundBePlayedForCallTerminationType:(enum CallTerminationType)type {
    [_soundPlayer stopAllAudio];
    if (type == CallTerminationType_RejectedLocal || type == CallTerminationType_RejectedRemote ||
        type == CallTerminationType_HangupLocal || type == CallTerminationType_HangupRemote ||
        type == CallTerminationType_RecipientUnavailable) {
        return NO;
    }
    return YES;
}

- (void)handleInboundRing {
    [_soundPlayer playSound:[SoundBoard instanceOfInboundRingtone]];
}

- (void)handleOutboundRing {
    [self setAudioProfile:AudioProfile_Default];
    [_soundPlayer playSound:[SoundBoard instanceOfOutboundRingtone]];
}

- (void)handleSecuring {
    [_soundPlayer stopAllAudio];
    [self setAudioProfile:AudioProfile_Default];
    [_soundPlayer playSound:[SoundBoard instanceOfHandshakeSound]];
}

- (void)handleCallEstablished {
    [_soundPlayer stopAllAudio];
    [self setAudioProfile:AudioProfile_Default];
    [_soundPlayer playSound:[SoundBoard instanceOfCompletedSound]];
}

- (BOOL)toggleSpeakerPhone {
    isSpeakerphoneActive = !isSpeakerphoneActive;
    [self updateAudioRouter];

    return isSpeakerphoneActive;
}

#pragma mark Audio Control

- (void)cancellAllAudio {
    [_soundPlayer stopAllAudio];
}

- (BOOL)requestRecordingPrivilege {
    return [self changeAudioSessionCategoryTo:RECORDING_CATEGORY];
}

- (BOOL)releaseRecordingPrivilege {
    return [self changeAudioSessionCategoryTo:DEFAULT_CATEGORY];
}

- (void)requestRequiredPermissionsIfNeededWithCompletion:(PermissionBlock)permissionBlock incoming:(BOOL)isIncoming {
    [AVAudioSession.sharedInstance requestRecordPermission:^(BOOL granted) {
      if (!granted) {
          UIAlertView *alertView =
              [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"ACTION_REQUIRED_TITLE", @"")
                                         message:NSLocalizedString(@"AUDIO_PERMISSION_MESSAGE", @"")
                                        delegate:nil
                               cancelButtonTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                               otherButtonTitles:NSLocalizedString(@"SETTINGS_NAV_BAR_TITLE", nil), nil];

          [alertView setDelegate:self];

          [alertView show];
      }

      permissionBlock(granted);
    }];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) { // Tapped the Settings button
        NSURL *appSettings = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
        [[UIApplication sharedApplication] openURL:appSettings];
    }
}

- (BOOL)changeAudioSessionCategoryTo:(NSString *)category {
    NSError *e;
    [AVAudioSession.sharedInstance setCategory:category error:&e];
    return (nil != e);
}

- (BOOL)setAudioEnabled:(BOOL)enable {
    NSError *e;
    if (enable) {
        [[AVAudioSession sharedInstance] setActive:enable error:&e];
        [_soundPlayer awake];
    } else {
        [[AVAudioSession sharedInstance] setActive:enable
                                       withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                             error:&e];
    }
    return (nil != e);
}

- (void)awake {
    [_soundPlayer awake];
}

#pragma mark Sound Player Delegate

- (void)didCompleteSoundInstanceOfType:(SoundInstanceType)instanceType {
    if (instanceType == SoundInstanceTypeBusySound || instanceType == SoundInstanceTypeErrorAlert ||
        instanceType == SoundInstanceTypeAlert) {
        [sharedAppAudioManager setAudioEnabled:NO];
    }
}


@end
