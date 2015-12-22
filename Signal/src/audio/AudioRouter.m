#import "AudioRouter.h"

#import <AVFoundation/AVAudioSession.h>

#define DEFAULT_CATAGORY AVAudioSessionCategoryPlayAndRecord

@implementation AudioRouter

+ (void)restoreDefaults {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    [session setActive:YES error:nil];
    [AudioRouter routeAllAudioToExternalSpeaker];
}

+ (void)routeAllAudioToInteralSpeaker {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    [session setCategory:DEFAULT_CATAGORY error:nil];
}

+ (void)routeAllAudioToExternalSpeaker {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    [session setCategory:DEFAULT_CATAGORY withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error:nil];
}

+ (BOOL)isOutputRoutedToSpeaker {
    AVAudioSession *session                   = AVAudioSession.sharedInstance;
    AVAudioSessionRouteDescription *routeDesc = session.currentRoute;

    for (AVAudioSessionPortDescription *portDesc in routeDesc.outputs) {
        if (AVAudioSessionPortBuiltInSpeaker == [portDesc portType]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)isOutputRoutedToReciever {
    AVAudioSession *session                   = AVAudioSession.sharedInstance;
    AVAudioSessionRouteDescription *routeDesc = session.currentRoute;

    for (AVAudioSessionPortDescription *portDesc in routeDesc.outputs) {
        if (AVAudioSessionPortBuiltInReceiver == [portDesc portType]) {
            return YES;
        }
    }
    return NO;
}

@end
