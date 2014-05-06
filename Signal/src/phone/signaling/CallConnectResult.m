#import "CallConnectResult.h"

@implementation CallConnectResult

@synthesize audioSocket, shortAuthenticationString;

+(CallConnectResult*) callConnectResultWithShortAuthenticationString:(NSString*)shortAuthenticationString
                                                      andAudioSocket:(AudioSocket*)audioSocket {
    require(shortAuthenticationString != nil);
    require(audioSocket != nil);
    
    CallConnectResult* result = [CallConnectResult new];
    result->shortAuthenticationString = shortAuthenticationString;
    result->audioSocket = audioSocket;
    return result;
}

@end
