#import "EncodedAudioPacket.h"
#import "Constraints.h"

@interface EncodedAudioPacket ()

@property (strong, readwrite, nonatomic) NSData* audioData;
@property (readwrite, nonatomic) uint16_t sequenceNumber;

@end

@implementation EncodedAudioPacket

- (instancetype)initWithAudioData:(NSData*)audioData andSequenceNumber:(uint16_t)sequenceNumber {
    self = [super init];
	
    if (self) {
        require(audioData != nil);
        
        self.audioData = audioData;
        self.sequenceNumber = sequenceNumber;
    }
    
    return self;
}

@end
