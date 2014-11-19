#import "AppAudioManager.h"
#import <AVFoundation/AVAudioSession.h>
#import "AudioRouter.h"
#import "SoundBoard.h"
#import "SoundPlayer.h"

#define DEFAULT_CATEGORY AVAudioSessionCategorySoloAmbient
#define RECORDING_CATEGORY AVAudioSessionCategoryPlayAndRecord

@interface AppAudioManager ()

@property (nonatomic) BOOL isSpeakerphoneActive;

@end

@implementation AppAudioManager

#pragma mark Creation

+ (instancetype)sharedInstance {
    static AppAudioManager* sharedInstance = nil;
    static dispatch_once_t onceToken = 0;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[AppAudioManager alloc] init];
        [[SoundPlayer sharedInstance] setDelegate:sharedInstance];
    });
    return sharedInstance;
}

#pragma mark AudioState Management

@synthesize audioProfile = _audioProfile;

- (void)setAudioProfile:(AudioProfile)audioProfile {
    [self updateAudioRouter];
     _audioProfile = audioProfile;
}

- (void)updateAudioRouter {
    if (self.isSpeakerphoneActive) {
        [AudioRouter routeAllAudioToExternalSpeaker];
    } else {
        switch (self.audioProfile) {
            case AudioProfileDefault:
                [AudioRouter routeAllAudioToInteralSpeaker];
                break;
            case AudioProfileExternalSpeaker:
                [AudioRouter routeAllAudioToExternalSpeaker];
                break;
            default:
                DDLogError(@"Unhandled AudioProfile");
        }
    }
}

- (void)overrideAudioProfile {
    self.isSpeakerphoneActive = YES;
    [self updateAudioRouter];
}

- (void)resetOverride {
    self.isSpeakerphoneActive = NO;
    [self updateAudioRouter];
}

- (AudioProfile)getCurrentAudioProfile {
    return (self.isSpeakerphoneActive) ? AudioProfileExternalSpeaker : self.audioProfile;
}

#pragma mark AudioControl

- (void)respondToProgressChange:(CallProgressType)progressType
        forLocallyInitiatedCall:(BOOL)initiatedLocally {
    switch (progressType){
        case CallProgressTypeConnecting:
            [self setAudioEnabled:YES];
            [[SoundPlayer sharedInstance] stopAllAudio];
        case CallProgressTypeRinging:
            (initiatedLocally) ? [self handleOutboundRing] : [self handleInboundRing];
            break;
        case CallProgressTypeTerminated:
            break;
        case CallProgressTypeSecuring:
            [self handleSecuring];
            break;
        case CallProgressTypeTalking:
            [self handleCallEstablished];
            break;
    }
}

- (void)respondToTerminationType:(CallTerminationType)terminationType {
    if (terminationType == CallTerminationTypeResponderIsBusy) {
        [[SoundPlayer sharedInstance] playSound:[SoundBoard instanceOfBusySound]];
    } else if ([self shouldErrorSoundBePlayedForCallTerminationType:terminationType]) {
        [[SoundPlayer sharedInstance] stopAllAudio];
        [[SoundPlayer sharedInstance] playSound:[SoundBoard instanceOfErrorAlert]];
    } else {
        [[SoundPlayer sharedInstance] playSound:[SoundBoard instanceOfAlert]];
    }
}

- (BOOL)shouldErrorSoundBePlayedForCallTerminationType:(CallTerminationType)type {
    if (type == CallTerminationTypeRejectedLocal  ||
        type == CallTerminationTypeRejectedRemote ||
        type == CallTerminationTypeHangupLocal    ||
        type == CallTerminationTypeHangupRemote   ||
        type == CallTerminationTypeRecipientUnavailable) {
        return NO;
    }
    return YES;
}

- (void)handleInboundRing {
    [[SoundPlayer sharedInstance] playSound:[SoundBoard instanceOfInboundRingtone]];
}

- (void)handleOutboundRing {
    [self setAudioProfile:AudioProfileDefault];
    [[SoundPlayer sharedInstance] playSound:[SoundBoard instanceOfOutboundRingtone]];
}

- (void)handleSecuring {
    [[SoundPlayer sharedInstance] stopAllAudio];
    [self setAudioProfile:AudioProfileDefault];
    [[SoundPlayer sharedInstance] playSound:[SoundBoard instanceOfHandshakeSound]];
}

- (void)handleCallEstablished {
    [[SoundPlayer sharedInstance] stopAllAudio];
    [self setAudioProfile:AudioProfileDefault];
    [[SoundPlayer sharedInstance] playSound:[SoundBoard instanceOfCompletedSound]];
}

- (BOOL)toggleSpeakerPhone {
    self.isSpeakerphoneActive = !self.isSpeakerphoneActive;
    [self updateAudioRouter];
    
    return self.isSpeakerphoneActive;
}

#pragma mark Audio Control

- (void)cancellAllAudio {
    [[SoundPlayer sharedInstance] stopAllAudio];
}

- (BOOL)requestRecordingPrivlege {
    return [self changeAudioSessionCategoryTo:RECORDING_CATEGORY];
}

- (BOOL)releaseRecordingPrivlege {
    return [self changeAudioSessionCategoryTo:DEFAULT_CATEGORY];
}

- (void)requestRequiredPermissionsIfNeeded {
    [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
        if (!granted) {
#warning Deprecated method
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"ACTION_REQUIRED_TITLE", @"")
                                                                message:NSLocalizedString(@"AUDIO_PERMISSION_MESSAGE", @"")
                                                               delegate:nil
                                                      cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                                      otherButtonTitles:nil, nil];
            [alertView show];
        }
    }];
}

- (BOOL)changeAudioSessionCategoryTo:(NSString*)category {
    NSError* e;
    [[AVAudioSession sharedInstance] setCategory:category error:&e];
    return (nil != e);
}

- (BOOL)setAudioEnabled:(BOOL)enable {
    NSError* e;
    if (enable) {
        [[AVAudioSession sharedInstance] setActive:enable error:&e];
        [[SoundPlayer sharedInstance] awake];
    } else {
        [[AVAudioSession sharedInstance] setActive:enable
                                       withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                             error:&e];
    }
    return (nil !=e);
}

- (void)awake {
    [[SoundPlayer sharedInstance] awake];
}

#pragma mark Sound Player Delegate

- (void)didCompleteSoundInstanceOfType:(SoundInstanceType)instanceType {
    if (instanceType == SoundInstanceTypeBusySound ||
        instanceType == SoundInstanceTypeErrorAlert ||
        instanceType == SoundInstanceTypeAlert) {
        [self setAudioEnabled:NO];
    }
}
    

@end
