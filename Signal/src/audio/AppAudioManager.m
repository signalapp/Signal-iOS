#import "AppAudioManager.h"

#import <AVFoundation/AVAudioSession.h>

#import "AudioRouter.h"
#import "SoundBoard.h"
#import "SoundPlayer.h"


#define DEFAULT_CATEGORY AVAudioSessionCategorySoloAmbient
#define RECORDING_CATEGORY AVAudioSessionCategoryPlayAndRecord


AppAudioManager*  sharedAppAudioManager;

@interface AppAudioManager (){
    enum AudioProfile _audioProfile;
    BOOL isSpeakerphoneActive;
}
@property (retain) SoundPlayer *soundPlayer;
@end


@implementation AppAudioManager

+(AppAudioManager*) sharedInstance {
    @synchronized(self){
        if( nil == sharedAppAudioManager){
            sharedAppAudioManager = [AppAudioManager new];
            sharedAppAudioManager.soundPlayer = [SoundPlayer new];
            [[sharedAppAudioManager soundPlayer] setDelegate:sharedAppAudioManager];
        }
    }
    return sharedAppAudioManager;
}

#pragma mark AudioState Management

-(void) setAudioProfile:(enum AudioProfile) profile {
    [self updateAudioRouter];
     _audioProfile = profile;
}

-(void) updateAudioRouter{
    if (isSpeakerphoneActive){
        [AudioRouter routeAllAudioToExternalSpeaker];
    }else{
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


-(void) overrideAudioProfile{
    isSpeakerphoneActive = YES;
    [self updateAudioRouter];
}

-(void) resetOverride{
    isSpeakerphoneActive = NO;
    [self updateAudioRouter];
}

-(enum AudioProfile) getCurrentAudioProfile{
    return (isSpeakerphoneActive) ? AudioProfile_ExternalSpeaker : _audioProfile;
}

#pragma mark AudioControl;
-(void) respondToProgressChange:(CallProgressType) progressType
        forLocallyInitiatedCall:(BOOL) initiatedLocally {
    switch (progressType){
        case CallProgressTypeConnecting:
            [sharedAppAudioManager setAudioEnabled:YES];
            [_soundPlayer stopAllAudio];
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

-(void) respondToTerminationType:(CallTerminationType) terminationType {
    if(terminationType == CallTerminationTypeResponderIsBusy) {
        [_soundPlayer playSound:[SoundBoard instanceOfBusySound]];
    }
    else if([self shouldErrorSoundBePlayedForCallTerminationType:terminationType]){
        [_soundPlayer playSound:[SoundBoard instanceOfErrorAlert]];
    }
    else {
        [_soundPlayer playSound:[SoundBoard instanceOfAlert]];
    }
}

-(BOOL) shouldErrorSoundBePlayedForCallTerminationType:(CallTerminationType) type{
    [_soundPlayer stopAllAudio];
    if (type == CallTerminationTypeRejectedLocal  ||
        type == CallTerminationTypeRejectedRemote ||
        type == CallTerminationTypeHangupLocal    ||
        type == CallTerminationTypeHangupRemote   ||
        type == CallTerminationTypeRecipientUnavailable) {
        return NO;
    }
    return YES;
}

-(void) handleInboundRing {
    [_soundPlayer playSound:[SoundBoard instanceOfInboundRingtone]];
}

-(void) handleOutboundRing {
    [self setAudioProfile:AudioProfile_Default];
    [_soundPlayer playSound:[SoundBoard instanceOfOutboundRingtone]];
}

-(void) handleSecuring {
    [_soundPlayer stopAllAudio];
    [self setAudioProfile:AudioProfile_Default];
    [_soundPlayer playSound:[SoundBoard instanceOfHandshakeSound]];
}

-(void) handleCallEstablished {
    [_soundPlayer stopAllAudio];
    [self setAudioProfile:AudioProfile_Default];
    [_soundPlayer playSound:[SoundBoard instanceOfCompletedSound]];
}

-(BOOL) toggleSpeakerPhone {
    isSpeakerphoneActive=!isSpeakerphoneActive;
    [self updateAudioRouter];
    
    return isSpeakerphoneActive;
}

#pragma mark Audio Control

-(void) cancellAllAudio {
    [_soundPlayer stopAllAudio];
}

-(BOOL) requestRecordingPrivlege {
    return [self changeAudioSessionCategoryTo:RECORDING_CATEGORY];
}

-(BOOL) releaseRecordingPrivlege{
    return [self changeAudioSessionCategoryTo:DEFAULT_CATEGORY];
}

-(void) requestRequiredPermissionsIfNeeded {
    [AVAudioSession.sharedInstance requestRecordPermission:^(BOOL granted) {
        if (!granted) {
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"ACTION_REQUIRED_TITLE", @"") message:NSLocalizedString(@"AUDIO_PERMISSION_MESSAGE", @"") delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", @"") otherButtonTitles:nil, nil];
            [alertView show];
        }
    }];
}

-(BOOL) changeAudioSessionCategoryTo:(NSString*) category {
    NSError* e;
    [AVAudioSession.sharedInstance setCategory:category error:&e];
    return (nil != e);
}

-(BOOL) setAudioEnabled:(BOOL) enable {
    NSError* e;
    if (enable) {
        [[AVAudioSession sharedInstance] setActive:enable error:&e];
        [_soundPlayer awake];
    } else {
        [[AVAudioSession sharedInstance] setActive:enable
                                       withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                             error:&e];
    }
    return ( nil !=e );
}

-(void) awake {
    [_soundPlayer awake];
}

#pragma mark Sound Player Delegate

- (void)didCompleteSoundInstanceOfType:(SoundInstanceType)instanceType {
    if (instanceType == SoundInstanceTypeBusySound ||
        instanceType == SoundInstanceTypeErrorAlert ||
        instanceType == SoundInstanceTypeAlert) {
        [sharedAppAudioManager setAudioEnabled:NO];
    }
}
    

@end
