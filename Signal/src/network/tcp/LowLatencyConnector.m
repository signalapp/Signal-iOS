#import "LowLatencyConnector.h"

#import "Constraints.h"
#import "Util.h"

@implementation LowLatencyConnector

+(TOCFuture*) asyncLowLatencyConnectToEndPoint:(id<NetworkEndPoint>)endPoint
                                untilCancelled:(TOCCancelToken*)untilCancelledToken {
    
    ows_require(endPoint != nil);
    
    TOCFuture* futureSpecificEndPoints = [endPoint asyncResolveToSpecificEndPointsUnlessCancelled:untilCancelledToken];
    
    return [futureSpecificEndPoints thenTry:^(NSArray* specificEndPoints) {
        return [LowLatencyConnector startConnectingToAll:specificEndPoints
                                          untilCancelled:untilCancelledToken];
    }];
}

+(TOCFuture*) startConnectingToAll:(NSArray*)specificEndPoints
                    untilCancelled:(TOCCancelToken*)untilCancelledToken {
    
    ows_require(specificEndPoints != nil);
    
    NSArray* candidates = [specificEndPoints map:^id(id<NetworkEndPoint> endPoint) {
        return [LowLatencyCandidate lowLatencyCandidateToRemoteEndPoint:endPoint];
    }];
    
    for (LowLatencyCandidate* candidate in candidates) {
        [candidate preStart];
    }
    
    NSArray* candidateCompleters = [candidates map:^id(LowLatencyCandidate* candidate) {
        return [candidate tcpHandshakeCompleter];
    }];
    
    TOCFuture* futureFastestCandidate = [candidateCompleters toc_raceForWinnerLastingUntil:untilCancelledToken];
    
    return [futureFastestCandidate thenTry:^(LowLatencyCandidate* fastestCandidate) {
        return [fastestCandidate delayedUntilAuthenticated];
    }];
}

@end
