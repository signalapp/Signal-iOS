#import "CallConnectResult.h"

@implementation CallConnectResult

@synthesize audioSocket, shortAuthenticationString;

+ (CallConnectResult *)callConnectResultWithShortAuthenticationString:(NSString *)shortAuthenticationString
                                                       andAudioSocket:(AudioSocket *)audioSocket {
    ows_require(shortAuthenticationString != nil);
    ows_require(audioSocket != nil);

    CallConnectResult *result         = [CallConnectResult new];
    result->shortAuthenticationString = shortAuthenticationString;
    result->audioSocket               = audioSocket;
    return result;
}

@end
