#import "RemoteIOBufferListWrapper.h"

@interface RemoteIOBufferListWrapper ()

@property (readwrite, nonatomic) AudioBufferList* audioBufferList;

@end

@implementation RemoteIOBufferListWrapper

- (instancetype)initWithMonoBufferSize:(NSUInteger)bufferSize {
    self = [super init];
	
    if (self) {
        self.audioBufferList = malloc(sizeof(AudioBufferList));
        self.audioBufferList->mNumberBuffers = 1;
        self.audioBufferList->mBuffers[0].mNumberChannels = 1;
        self.audioBufferList->mBuffers[0].mDataByteSize = (UInt32)bufferSize;
        self.audioBufferList->mBuffers[0].mData = malloc(bufferSize);
    }
    
    return self;
}

- (void)dealloc {
    free(self.audioBufferList->mBuffers[0].mData);
}

@end
