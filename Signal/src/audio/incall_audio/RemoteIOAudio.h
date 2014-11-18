#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "AudioCallbackHandler.h"
#import "CyclicalBuffer.h"
#import "Environment.h"
#import "RemoteIOBufferListWrapper.h"
#import "Terminable.h"

typedef NS_ENUM(NSInteger, RemoteIOAudioState) {
    RemoteIOAudioStateNotStarted,
    RemoteIOAudioStateStarted,
    RemoteIOAudioStateTerminated
};

/**
 *
 * RemoteIOAudio is responsible for playing audio through the speakers and 
 * recording audio through the microphone.  It sends/receives this information
 * to/from its AudioCallbackHandler delegate.
 *
 * Uses Apple's Remote I/O AudioUnit, for simultaneous input and output of audio.
 * The AudioUnit provides format conversion between the hardware audio formats
 * and Redphone's audio format.
 *
 */

@interface RemoteIOAudio : NSObject <AVAudioSessionDelegate>

@property (readonly, nonatomic) RemoteIOAudioState state;
@property (strong)              CyclicalBuffer*    recordingQueue;
@property (strong)              CyclicalBuffer*    playbackQueue;
@property (assign)              AudioUnit          rioAudioUnit;

- (instancetype)initWithDelegate:(id<AudioCallbackHandler>)delegateIn untilCancelled:(TOCCancelToken*)untilCancelledToken;
- (void)populatePlaybackQueueWithData:(NSData*)data;
- (NSUInteger)getSampleRateInHertz;
- (BOOL)toggleMute;

@end

