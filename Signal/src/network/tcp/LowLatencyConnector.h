#import <Foundation/Foundation.h>
#import "CollapsingFutures.h"
#import "IpEndPoint.h"
#import "NetworkStream.h"
#import "LowLatencyCandidate.h"

/**
 *
 * Responsible for racing connections to all ip addresses associated with a host name simulatenously.
 * The first connection to complete its tcp handshake wins.
 *
 **/

@interface LowLatencyConnector : NSObject <NSStreamDelegate>

/// Result has type Future(LowLatencyCandidate).
+(TOCFuture*) asyncLowLatencyConnectToEndPoint:(id<NetworkEndPoint>)endPoint
                                untilCancelled:(TOCCancelToken*)untilCancelledToken;

@end
