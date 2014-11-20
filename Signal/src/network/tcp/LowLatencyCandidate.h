#import <Foundation/Foundation.h>
#import "CollapsingFutures.h"
#import "IPEndPoint.h"
#import "NetworkStream.h"

@interface LowLatencyCandidate : NSObject <Terminable>

@property (strong, readonly, nonatomic) IPEndPoint* remoteEndPoint;
@property (strong, readonly, nonatomic) NetworkStream* networkStream;

- (instancetype)initWithRemoteEndPoint:(id<NetworkEndPoint>)remoteEndPoint;

- (void)preStart;

- (TOCUntilOperation)tcpHandshakeCompleter;

- (TOCFuture*)delayedUntilAuthenticated;

@end
