#import "EncodedAudioFrame.h"
#import "Constraints.h"

@interface EncodedAudioFrame ()

@property (strong, readwrite, nonatomic, getter=tryGetAudioData) NSData* audioData;

@end

@implementation EncodedAudioFrame

- (instancetype)initWithData:(NSData*)audioData {
    self = [super init];
	
    if (self) {
        require(audioData != nil);
        
        self.audioData = audioData;
    }
    
    return self;
}

+ (instancetype)emptyFrame {
    return [[self alloc] init];
}

- (bool)isMissingAudioData {
    return self.audioData == nil;
}

@end
