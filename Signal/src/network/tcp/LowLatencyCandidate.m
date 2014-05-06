#import "LowLatencyCandidate.h"
#import "Util.h"

@implementation LowLatencyCandidate

@synthesize networkStream, remoteEndPoint;

+(LowLatencyCandidate*) lowLatencyCandidateToRemoteEndPoint:(id<NetworkEndPoint>)remoteEndPoint {
    
    require(remoteEndPoint != nil);
    
    LowLatencyCandidate* r = [LowLatencyCandidate new];
    r->remoteEndPoint = remoteEndPoint;
    r->networkStream = [NetworkStream networkStreamToEndPoint:remoteEndPoint];
    return r;
}

-(void)terminate {
    [networkStream terminate];
}

-(void) preStart {
    [networkStream startProcessingStreamEventsEvenWithoutHandler];
}

-(CancellableOperationStarter) tcpHandshakeCompleter {
    return ^(id<CancelToken> untilCancelledToken) {
        return [self completer:untilCancelledToken];
    };
}

-(Future*) completer:(id<CancelToken>)untilCancelledToken {
    Future* tcpHandshakeCompleted = [networkStream asyncTcpHandshakeCompleted];
    
    [untilCancelledToken whenCancelledTerminate:self];
    
    return [Future delayed:self
                untilAfter:tcpHandshakeCompleted];
}

-(Future*) delayedUntilAuthenticated {
    return [Future delayed:self
                untilAfter:[networkStream asyncConnectionCompleted]];
}

@end
