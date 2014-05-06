#import "LowLatencyConnector.h"
#import "Constraints.h"
#import "Util.h"
#import "DnsManager.h"
#import "IpAddress.h"
#import "CancelToken.h"
#import "FunctionalUtil.h"
#import "AsyncUtil.h"
#import "NetworkStream.h"

@implementation LowLatencyConnector

+(Future*) asyncLowLatencyConnectToEndPoint:(id<NetworkEndPoint>)endPoint
                             untilCancelled:(id<CancelToken>)untilCancelledToken {
    
    require(endPoint != nil);
    
    Future* futureSpecificEndPoints = [endPoint asyncResolveToSpecificEndPointsUnlessCancelled:untilCancelledToken];
    
    return [futureSpecificEndPoints then:^(NSArray* specificEndPoints) {
        return [LowLatencyConnector startConnectingToAll:specificEndPoints
                                          untilCancelled:untilCancelledToken];
    }];
}

+(Future*) startConnectingToAll:(NSArray*)specificEndPoints
                 untilCancelled:(id<CancelToken>)untilCancelledToken {
    
    require(specificEndPoints != nil);
    
    
    NSArray* candidates = [specificEndPoints map:^id(id<NetworkEndPoint> endPoint) {
        return [LowLatencyCandidate lowLatencyCandidateToRemoteEndPoint:endPoint];
    }];

    for (LowLatencyCandidate* candidate in candidates) {
        [candidate preStart];
    }
    
    NSArray* candidateCompleters = [candidates map:^id(LowLatencyCandidate* candidate) {
        return [candidate tcpHandshakeCompleter];
    }];

    Future* futureFastestCandidate = [AsyncUtil raceCancellableOperations:candidateCompleters
                                                           untilCancelled:untilCancelledToken];
    
    return [futureFastestCandidate then:^(LowLatencyCandidate* fastestCandidate) {
        return [fastestCandidate delayedUntilAuthenticated];
    }];
}

@end
