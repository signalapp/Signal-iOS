#import <Foundation/Foundation.h>

#import "MasterSecret.h"
#import "SRTPSocket.h"

/**
 *
 * A ZRTPHandshakeResult stores the master secret and secure rtp communication channel produced by a successful zrtp handshake.
 *
**/

@interface ZRTPHandshakeResult : NSObject

@property (strong, readonly, nonatomic) SRTPSocket* secureRTPSocket;
@property (strong, readonly, nonatomic) MasterSecret* masterSecret;

- (instancetype)initWithSecureChannel:(SRTPSocket*)secureRTPSocket
                      andMasterSecret:(MasterSecret*)masterSecret;

@end
