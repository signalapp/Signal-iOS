#import "EncodedAudioFrame.h"
#import "Constraints.h"

@interface EncodedAudioFrame ()

@property (strong, readwrite, nonatomic, getter=tryGetAudioData) NSData* audioData;

@end

@implementation EncodedAudioFrame

- (instancetype)initWithData:(NSData*)audioData {
    if (self = [super init]) {
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
