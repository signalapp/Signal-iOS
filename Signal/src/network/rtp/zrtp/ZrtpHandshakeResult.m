#import "ZrtpHandshakeResult.h"

@implementation ZrtpHandshakeResult

@synthesize masterSecret, secureRtpSocket;

+(ZrtpHandshakeResult*) zrtpHandshakeResultWithSecureChannel:(SrtpSocket*)secureRtpSocket andMasterSecret:(MasterSecret*)masterSecret {
    require(secureRtpSocket != nil);
    require(masterSecret != nil);
    
    ZrtpHandshakeResult* z = [ZrtpHandshakeResult new];
    z->masterSecret = masterSecret;
    z->secureRtpSocket = secureRtpSocket;
    return z;
}

@end
