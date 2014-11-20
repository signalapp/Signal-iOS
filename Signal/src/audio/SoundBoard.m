#import "SoundBoard.h"

static NSString* SoundFile_Alert     =@"171756__nenadsimic__picked-coin-echo-2.wav";
static NSString* SoundFile_Busy      =@"busy.mp3";
static NSString* SoundFile_Completed =@"completed.mp3";
static NSString* SoundFile_Failure   =@"failure.mp3";
static NSString* SoundFile_Handshake =@"handshake.mp3";
static NSString* SoundFile_Outbound  =@"outring.mp3";
static NSString* SoundFile_Ringtone  =@"r.caf";

@implementation SoundBoard

+ (SoundInstance*)instanceOfInboundRingtone {
    SoundInstance* soundInstance = [[SoundInstance alloc] initWithFile:SoundFile_Ringtone
                                                  andSoundInstanceType:SoundInstanceTypeInboundRingtone];
    [soundInstance setAudioToLoopIndefinitely];
    return soundInstance;
}

+ (SoundInstance*)instanceOfOutboundRingtone {
    SoundInstance* soundInstance = [[SoundInstance alloc] initWithFile:SoundFile_Outbound
                                                  andSoundInstanceType:SoundInstanceTypeOutboundRingtone];
    [soundInstance setAudioToLoopIndefinitely];
    return soundInstance;
}

+ (SoundInstance*)instanceOfHandshakeSound {
    SoundInstance* soundInstance = [[SoundInstance alloc] initWithFile:SoundFile_Handshake
                                                  andSoundInstanceType:SoundInstanceTypeHandshakeSound];
    [soundInstance setAudioToLoopIndefinitely];
    return soundInstance;
}

+ (SoundInstance*)instanceOfCompletedSound {
    SoundInstance* soundInstance = [[SoundInstance alloc] initWithFile:SoundFile_Completed
                                                  andSoundInstanceType:SoundInstanceTypeCompletedSound];
    return soundInstance;
}

+ (SoundInstance*)instanceOfBusySound {
    SoundInstance* soundInstance = [[SoundInstance alloc] initWithFile:SoundFile_Busy
                                                  andSoundInstanceType:SoundInstanceTypeBusySound];
    [soundInstance setAudioLoopCount:10];
    return soundInstance;
}

+ (SoundInstance*)instanceOfErrorAlert {
    SoundInstance* soundInstance = [[SoundInstance alloc] initWithFile:SoundFile_Failure
                                                  andSoundInstanceType:SoundInstanceTypeErrorAlert];
    return soundInstance;
}

+ (SoundInstance*)instanceOfAlert {
    SoundInstance* soundInstance = [[SoundInstance alloc] initWithFile:SoundFile_Alert
                                                  andSoundInstanceType:SoundInstanceTypeAlert];
    return soundInstance;
}



@end
