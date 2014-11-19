#import "AudioRouter.h"
#import <AVFoundation/AVAudioSession.h>

#define DEFAULT_CATAGORY AVAudioSessionCategoryPlayAndRecord

@implementation AudioRouter

+ (void)restoreDefaults {
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    [AudioRouter routeAllAudioToExternalSpeaker];
}

+ (void)routeAllAudioToInteralSpeaker {
    [[AVAudioSession sharedInstance] setCategory:DEFAULT_CATAGORY error:nil];
}

+ (void)routeAllAudioToExternalSpeaker {
    [[AVAudioSession sharedInstance] setCategory:DEFAULT_CATAGORY
                                     withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker
                                           error:nil];
}

+ (BOOL)isOutputRoutedToSpeaker {
    AVAudioSessionRouteDescription* routeDesc = [AVAudioSession sharedInstance].currentRoute;
    
    for (AVAudioSessionPortDescription* portDesc in routeDesc.outputs) {
        if (AVAudioSessionPortBuiltInSpeaker == [portDesc portType]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)isOutputRoutedToReciever {
    AVAudioSessionRouteDescription* routeDesc = [AVAudioSession sharedInstance].currentRoute;
    
    for (AVAudioSessionPortDescription* portDesc in routeDesc.outputs) {
        if (AVAudioSessionPortBuiltInReceiver == [portDesc portType]) {
            return YES;
        }
    }
    return NO;
}

@end
