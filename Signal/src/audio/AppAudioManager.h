#import <Foundation/Foundation.h>

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

typedef NS_ENUM(NSInteger, AudioProfile) {
    AudioProfileDefault,
    AudioProfileExternalSpeaker
};

@interface AppAudioManager : NSObject <SoundPlayerDelegate>

@property (nonatomic, getter=getCurrentAudioProfile) AudioProfile audioProfile;

+ (instancetype)sharedInstance;

- (void)respondToProgressChange:(CallProgressType)progressType forLocallyInitiatedCall:(BOOL)initiatedLocally;
- (void)respondToTerminationType:(CallTerminationType)terminationType;

- (BOOL)toggleSpeakerPhone;
- (void)cancellAllAudio;

- (void)requestRequiredPermissionsIfNeeded;
- (BOOL)requestRecordingPrivlege;
- (BOOL)releaseRecordingPrivlege;

- (BOOL)setAudioEnabled:(BOOL)enable;
- (void)awake;

- (void)didCompleteSoundInstanceOfType:(SoundInstanceType)instanceType;

@end
