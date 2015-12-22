#import <Foundation/Foundation.h>

#import <AVFoundation/AVAudioSession.h>
#import "CallProgress.h"
#import "CallTermination.h"
#import "SoundPlayer.h"

/**
 *  The AppAudioManager is a Singleton object used to control audio settings / updates
 *  for the entire application. This includes playing sounds appropriately, Initializing
 *  Audio Settings, and interfacing with the OS. The Call Audio Pipeline it self is delegated
 *  to the RemoteIOAudio Class.
 *
 *  The Audio Profile determines which preset of logic to use for playing sounds, Such as
 *  which speaker to use or if all sounds should be muted.
 **/

@interface AppAudioManager : NSObject <SoundPlayerDelegate>

enum AudioProfile {
    AudioProfile_Default,
    AudioProfile_ExternalSpeaker,
};

+ (AppAudioManager *)sharedInstance;

- (void)setAudioProfile:(enum AudioProfile)profile;
- (enum AudioProfile)getCurrentAudioProfile;
- (void)updateAudioRouter;

- (void)respondToProgressChange:(enum CallProgressType)progressType forLocallyInitiatedCall:(BOOL)initiatedLocally;
- (void)respondToTerminationType:(enum CallTerminationType)terminationType;

- (BOOL)toggleSpeakerPhone;
- (void)cancellAllAudio;

- (void)requestRequiredPermissionsIfNeededWithCompletion:(PermissionBlock)permissionBlock incoming:(BOOL)isIncoming;
- (BOOL)requestRecordingPrivilege;
- (BOOL)releaseRecordingPrivilege;

- (BOOL)setAudioEnabled:(BOOL)enable;
- (void)awake;

- (void)didCompleteSoundInstanceOfType:(SoundInstanceType)instanceType;

@end
