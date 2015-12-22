#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>
#import "AudioCallbackHandler.h"
#import "CyclicalBuffer.h"
#import "Environment.h"
#import "RemoteIOBufferListWrapper.h"
#import "Terminable.h"

enum State { NOT_STARTED, STARTED, TERMINATED };

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
@interface RemoteIOAudio : NSObject <AVAudioSessionDelegate> {
    AudioUnit rioAudioUnit;

    BOOL isStreaming;

    id<AudioCallbackHandler> delegate;

    NSMutableSet *unusedBuffers;

    id<OccurrenceLogger> starveLogger;
    id<ConditionLogger> conditionLogger;
    id<ValueLogger> playbackBufferSizeLogger;
    id<ValueLogger> recordingQueueSizeLogger;
}

@property (nonatomic, readonly) enum State state;
@property (strong) CyclicalBuffer *recordingQueue;
@property (strong) CyclicalBuffer *playbackQueue;
@property (assign) AudioUnit rioAudioUnit;

+ (RemoteIOAudio *)remoteIOInterfaceStartedWithDelegate:(id<AudioCallbackHandler>)delegateIn
                                         untilCancelled:(TOCCancelToken *)untilCancelledToken;
- (void)populatePlaybackQueueWithData:(NSData *)data;
- (NSUInteger)getSampleRateInHertz;
- (BOOL)toggleMute;

@end
