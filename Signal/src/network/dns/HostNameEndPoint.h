#import <Foundation/Foundation.h>
#import "NetworkEndPoint.h"

/**
 *
 * Stores the port and hostname for a resolvable network end point
 *
**/

@interface HostNameEndPoint : NSObject <NetworkEndPoint>

@property (nonatomic, readonly) in_port_t port;
@property (strong, nonatomic, readonly) NSString* hostname;

- (instancetype)initWithHostName:(NSString*)hostname
                         andPort:(in_port_t)port;

// Conform to NetworkEndPoint
- (StreamPair*)createStreamPair;
- (void) handleStreamsOpened:(StreamPair*)streamPair;
- (TOCFuture*)asyncHandleStreamsConnected:(StreamPair*)streamPair;
- (TOCFuture*)asyncResolveToSpecificEndPointsUnlessCancelled:(TOCCancelToken*)unlessCancelledToken;

@end
