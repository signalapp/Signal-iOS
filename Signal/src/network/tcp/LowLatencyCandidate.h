#import <Foundation/Foundation.h>
#import "CollapsingFutures.h"
#import "IpEndPoint.h"
#import "NetworkStream.h"

@interface LowLatencyCandidate : NSObject<Terminable>

@property (readonly,nonatomic) IpEndPoint* remoteEndPoint;
@property (readonly,nonatomic) NetworkStream* networkStream;

+(LowLatencyCandidate*) lowLatencyCandidateToRemoteEndPoint:(id<NetworkEndPoint>)remoteEndPoint;

-(void) preStart;

-(TOCUntilOperation) tcpHandshakeCompleter;

-(TOCFuture*) delayedUntilAuthenticated;

@end
