#import "RemoteIOBufferListWrapper.h"

@implementation RemoteIOBufferListWrapper

@synthesize sampleCount, audioBufferList;

+ (RemoteIOBufferListWrapper *)remoteIOBufferListWithMonoBufferSize:(NSUInteger)bufferSize {
    AudioBufferList *audioBufferList             = malloc(sizeof(AudioBufferList));
    audioBufferList->mNumberBuffers              = 1;
    audioBufferList->mBuffers[0].mNumberChannels = 1;
    audioBufferList->mBuffers[0].mDataByteSize   = (UInt32)bufferSize;
    audioBufferList->mBuffers[0].mData           = malloc(bufferSize);

    RemoteIOBufferListWrapper *w = [RemoteIOBufferListWrapper new];
    w->audioBufferList           = audioBufferList;
    return w;
}
- (void)dealloc {
    free(audioBufferList->mBuffers[0].mData);
}

@end
