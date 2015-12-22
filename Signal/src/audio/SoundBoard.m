#import "SoundBoard.h"

static NSString *SoundFile_Alert     = @"171756__nenadsimic__picked-coin-echo-2.wav";
static NSString *SoundFile_Busy      = @"busy.mp3";
static NSString *SoundFile_Completed = @"completed.mp3";
static NSString *SoundFile_Failure   = @"failure.mp3";
static NSString *SoundFile_Handshake = @"handshake.mp3";
static NSString *SoundFile_Outbound  = @"outring.mp3";
static NSString *SoundFile_Ringtone  = @"r.caf";

@implementation SoundBoard

+ (SoundInstance *)instanceOfInboundRingtone {
    SoundInstance *soundInstance = [SoundInstance soundInstanceForFile:SoundFile_Ringtone];
    [soundInstance setAudioToLoopIndefinitely];
    [soundInstance setInstanceType:SoundInstanceTypeInboundRingtone];
    return soundInstance;
}

+ (SoundInstance *)instanceOfOutboundRingtone {
    SoundInstance *soundInstance = [SoundInstance soundInstanceForFile:SoundFile_Outbound];
    [soundInstance setAudioToLoopIndefinitely];
    [soundInstance setInstanceType:SoundInstanceTypeOutboundRingtone];
    return soundInstance;
}

+ (SoundInstance *)instanceOfHandshakeSound {
    SoundInstance *soundInstance = [SoundInstance soundInstanceForFile:SoundFile_Handshake];
    [soundInstance setAudioToLoopIndefinitely];
    [soundInstance setInstanceType:SoundInstanceTypeHandshakeSound];
    return soundInstance;
}

+ (SoundInstance *)instanceOfCompletedSound {
    SoundInstance *soundInstance = [SoundInstance soundInstanceForFile:SoundFile_Completed];
    [soundInstance setInstanceType:SoundInstanceTypeCompletedSound];
    return soundInstance;
}

+ (SoundInstance *)instanceOfBusySound {
    SoundInstance *soundInstance = [SoundInstance soundInstanceForFile:SoundFile_Busy];
    [soundInstance setAudioLoopCount:10];
    [soundInstance setInstanceType:SoundInstanceTypeBusySound];
    return soundInstance;
}

+ (SoundInstance *)instanceOfErrorAlert {
    SoundInstance *soundInstance = [SoundInstance soundInstanceForFile:SoundFile_Failure];
    [soundInstance setInstanceType:SoundInstanceTypeErrorAlert];
    return soundInstance;
}

+ (SoundInstance *)instanceOfAlert {
    SoundInstance *soundInstance = [SoundInstance soundInstanceForFile:SoundFile_Alert];
    [soundInstance setInstanceType:SoundInstanceTypeAlert];
    return soundInstance;
}


@end
