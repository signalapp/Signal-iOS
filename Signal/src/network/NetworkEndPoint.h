#import <Foundation/Foundation.h>
#import "CollapsingFutures.h"
#import "StreamPair.h"

/// Describes a location to which you can connect and communicate.
@protocol NetworkEndPoint <NSObject>

/// Creates a pair of read/write streams to this end point.
-(StreamPair*) createStreamPair;

/// Invoked when a stream pair has opened (tcp handshake completed), but before it is necessary writable.
/// (The time to set any options on the stream.)
-(void) handleStreamsOpened:(StreamPair*)streamPair;

/// Invoked when a stream pair is ready for read/write.
/// (The time to authenticate certificates of a completed SSL connection.)
-(TOCFuture*) asyncHandleStreamsConnected:(StreamPair*)streamPair;

/// Resolves this general end point into underlying associated specific end points.
/// For example, a hostname+port end point resolves into one or more ip+port end points.
/// The asynchronous result has type Future(Array(NetworkEndPoint)).
-(TOCFuture*) asyncResolveToSpecificEndPointsUnlessCancelled:(TOCCancelToken*)unlessCancelledToken;

@end
