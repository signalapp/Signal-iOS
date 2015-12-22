#import <Foundation/Foundation.h>
#import "SoundInstance.h"

/**
 *  SoundPlayer tracks and controls all Audiofiles being played. Currently only one instance
 *  of a given sound can be played at a given time. Attemping to play multiple intances of a
 *  sound is ignored. Multiple different sound instances can be played concurrently.
 */

@protocol SoundPlayerDelegate;

@interface SoundPlayer : NSObject

@property (strong, nonatomic) id<SoundPlayerDelegate> delegate;

- (void)playSound:(SoundInstance *)player;
- (void)stopSound:(SoundInstance *)player;

- (void)stopAllAudio;
- (void)awake;

@end

@protocol SoundPlayerDelegate <NSObject>

@optional
- (void)didCompleteSoundInstanceOfType:(SoundInstanceType)instanceType;

@end
