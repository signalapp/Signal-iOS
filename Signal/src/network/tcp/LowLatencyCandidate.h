#import <Foundation/Foundation.h>
#import "IpEndPoint.h"
#import "NetworkStream.h"
#import "AsyncUtil.h"

@interface LowLatencyCandidate : NSObject<Terminable>

@property (readonly,nonatomic) IpEndPoint* remoteEndPoint;
@property (readonly,nonatomic) NetworkStream* networkStream;

+(LowLatencyCandidate*) lowLatencyCandidateToRemoteEndPoint:(id<NetworkEndPoint>)remoteEndPoint;

-(void) preStart;

-(CancellableOperationStarter) tcpHandshakeCompleter;

-(Future*) delayedUntilAuthenticated;

@end
