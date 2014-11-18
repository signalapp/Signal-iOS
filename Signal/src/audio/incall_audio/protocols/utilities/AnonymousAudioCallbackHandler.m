#import "AnonymousAudioCallbackHandler.h"

@interface AnonymousAudioCallbackHandler ()

@property (readwrite, nonatomic, copy) void (^handleNewDataRecordedBlock)(CyclicalBuffer* data);
@property (readwrite, nonatomic, copy) void (^handlePlaybackOccurredWithBytesRequestedBlock)(NSUInteger requested, NSUInteger bytesRemaining);

@end

@implementation AnonymousAudioCallbackHandler

- (instancetype)initDelegateWithRecordingCallback:(void(^)(CyclicalBuffer* data))recordingCallback
                      andPlaybackOccurredCallback:(void(^)(NSUInteger requested, NSUInteger bytesRemaining))playbackCallback {
    if (self = [super init]) {
        self.handleNewDataRecordedBlock = recordingCallback;
        self.handlePlaybackOccurredWithBytesRequestedBlock = playbackCallback;
    }
    
    return self;
}

- (void)handleNewDataRecorded:(CyclicalBuffer*)data {
    if (self.handleNewDataRecordedBlock != nil)
        self.handleNewDataRecordedBlock(data);
}

- (void)handlePlaybackOccurredWithBytesRequested:(NSUInteger)requested andBytesRemaining:(NSUInteger)bytesRemaining {
    if (self.handlePlaybackOccurredWithBytesRequestedBlock != nil)
        self.handlePlaybackOccurredWithBytesRequestedBlock(requested, bytesRemaining);
}

@end
