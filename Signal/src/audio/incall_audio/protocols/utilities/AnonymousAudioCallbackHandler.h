#import <Foundation/Foundation.h>
#import "AudioCallbackHandler.h"

/**
 *
 * AnonymousAudioCallbackHandler implements AudioCallbackHandler with blocks passed to its constructor.
 *
 **/

@interface AnonymousAudioCallbackHandler : NSObject <AudioCallbackHandler>

@property (readonly, nonatomic, copy) void (^handleNewDataRecordedBlock)(CyclicalBuffer *data);
@property (readonly, nonatomic, copy) void (^handlePlaybackOccurredWithBytesRequestedBlock)
    (NSUInteger requested, NSUInteger bytesRemaining);

+ (AnonymousAudioCallbackHandler *)
anonymousAudioInterfaceDelegateWithRecordingCallback:(void (^)(CyclicalBuffer *data))recordingCallback
                         andPlaybackOccurredCallback:
                             (void (^)(NSUInteger requested, NSUInteger bytesRemaining))playbackCallback;

@end
