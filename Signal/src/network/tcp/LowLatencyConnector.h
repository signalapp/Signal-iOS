#import <Foundation/Foundation.h>
#import "IpEndPoint.h"
#import "FutureSource.h"
#import "NetworkStream.h"
#import "CancelToken.h"
#import "LowLatencyCandidate.h"

/**
 *
 * Responsible for racing connections to all ip addresses associated with a host name simulatenously.
 * The first connection to complete its tcp handshake wins.
 *
 **/

@interface LowLatencyConnector : NSObject <NSStreamDelegate>

/// Result has type Future(LowLatencyCandidate).
+(Future*) asyncLowLatencyConnectToEndPoint:(id<NetworkEndPoint>)endPoint
                             untilCancelled:(id<CancelToken>)untilCancelledToken;

@end
