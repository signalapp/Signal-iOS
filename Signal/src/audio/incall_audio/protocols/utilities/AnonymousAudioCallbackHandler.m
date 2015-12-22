#import "AnonymousAudioCallbackHandler.h"

@implementation AnonymousAudioCallbackHandler

+ (AnonymousAudioCallbackHandler *)
anonymousAudioInterfaceDelegateWithRecordingCallback:(void (^)(CyclicalBuffer *data))recordingCallback
                         andPlaybackOccurredCallback:
                             (void (^)(NSUInteger requested, NSUInteger bytesRemaining))playbackCallback {
    AnonymousAudioCallbackHandler *a                  = [AnonymousAudioCallbackHandler new];
    a->_handleNewDataRecordedBlock                    = recordingCallback;
    a->_handlePlaybackOccurredWithBytesRequestedBlock = playbackCallback;
    return a;
}
- (void)handleNewDataRecorded:(CyclicalBuffer *)data {
    if (_handleNewDataRecordedBlock != nil)
        _handleNewDataRecordedBlock(data);
}
- (void)handlePlaybackOccurredWithBytesRequested:(NSUInteger)requested andBytesRemaining:(NSUInteger)bytesRemaining {
    if (_handlePlaybackOccurredWithBytesRequestedBlock != nil)
        _handlePlaybackOccurredWithBytesRequestedBlock(requested, bytesRemaining);
}

@end
