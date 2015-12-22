#import "ZrtpHandshakeResult.h"

@implementation ZrtpHandshakeResult

@synthesize masterSecret, secureRtpSocket;

+(ZrtpHandshakeResult*) zrtpHandshakeResultWithSecureChannel:(SrtpSocket*)secureRtpSocket andMasterSecret:(MasterSecret*)masterSecret {
    ows_require(secureRtpSocket != nil);
    ows_require(masterSecret != nil);
    
    ZrtpHandshakeResult* z = [ZrtpHandshakeResult new];
    z->masterSecret = masterSecret;
    z->secureRtpSocket = secureRtpSocket;
    return z;
}

@end
