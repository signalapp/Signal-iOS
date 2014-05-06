#import <Foundation/Foundation.h>

#import "MasterSecret.h"
#import "SrtpSocket.h"

/**
 *
 * A ZrtpHandshakeResult stores the master secret and secure rtp communication channel produced by a successful zrtp handshake.
 *
**/

@interface ZrtpHandshakeResult : NSObject
@property (nonatomic,readonly) SrtpSocket* secureRtpSocket;
@property (nonatomic,readonly) MasterSecret* masterSecret;

+(ZrtpHandshakeResult*) zrtpHandshakeResultWithSecureChannel:(SrtpSocket*)secureRtpSocket andMasterSecret:(MasterSecret*)masterSecret;
@end
