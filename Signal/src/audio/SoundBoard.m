#import "SoundBoard.h"

static NSString* SoundFile_Alert     =@"171756__nenadsimic__picked-coin-echo-2.wav";
static NSString* SoundFile_Busy      =@"busy.mp3";
static NSString* SoundFile_Completed =@"completed.mp3";
static NSString* SoundFile_Failure   =@"failure.mp3";
static NSString* SoundFile_Handshake =@"handshake.mp3";
static NSString* SoundFile_Outbound  =@"outring.mp3";
static NSString* SoundFile_Ringtone  =@"r.caf";

@implementation SoundBoard

+(SoundInstance*) instanceOfInboundRingtone{
    SoundInstance* soundInstance = [SoundInstance soundInstanceForFile:SoundFile_Ringtone];
    [soundInstance setAudioToLoopIndefinitely];
    return soundInstance;
}

+(SoundInstance*) instanceOfOutboundRingtone{
    SoundInstance* soundInstance = [SoundInstance soundInstanceForFile:SoundFile_Outbound];
    [soundInstance setAudioToLoopIndefinitely];
    return soundInstance;
}

+(SoundInstance*) instanceOfHandshakeSound  {
    SoundInstance* soundInstance = [SoundInstance soundInstanceForFile:SoundFile_Handshake];
    [soundInstance setAudioToLoopIndefinitely];
    return soundInstance;
}

+(SoundInstance*) instanceOfCompletedSound {
    SoundInstance* soundInstance = [SoundInstance soundInstanceForFile:SoundFile_Completed];
    return soundInstance;
}

+(SoundInstance*) instanceOfBusySound {
    SoundInstance* soundInstance = [SoundInstance soundInstanceForFile:SoundFile_Busy];
    [soundInstance setAudioLoopCount:10];
    return soundInstance;
}

+(SoundInstance*) instanceOfErrorAlert {
    SoundInstance* soundInstance = [SoundInstance soundInstanceForFile:SoundFile_Failure];
    return soundInstance;
}

+(SoundInstance*) instanceOfAlert {
    SoundInstance* soundInstance = [SoundInstance soundInstanceForFile:SoundFile_Alert];
    return soundInstance;
}



@end
