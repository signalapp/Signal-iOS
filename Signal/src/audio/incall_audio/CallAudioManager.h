#import <Foundation/Foundation.h>
#import "AudioProcessor.h"
#import "AudioSocket.h"
#import "Environment.h"
#import "RemoteIOAudio.h"
#import "SpeexCodec.h"

/**
 *
 * CallAudioManager is responsible for creating and managing components related to playing real time audio communicated
 *over a network.
 *
 * The components are for playing/recording, processing, and transporting audio data.
 *
 **/

@interface CallAudioManager : NSObject <AudioCallbackHandler> {
   @private
    RemoteIOAudio *audioInterface;
   @private
    AudioProcessor *audioProcessor;
   @private
    AudioSocket *audioSocket;
   @private
    bool started;
   @private
    NSUInteger bytesInPlaybackBuffer;
}

+ (CallAudioManager *)callAudioManagerStartedWithAudioSocket:(AudioSocket *)audioSocket
                                             andErrorHandler:(ErrorHandlerBlock)errorHandler
                                              untilCancelled:(TOCCancelToken *)untilCancelledToken;
- (BOOL)toggleMute;
@end
