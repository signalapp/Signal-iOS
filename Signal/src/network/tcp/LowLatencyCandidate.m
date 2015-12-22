#import "LowLatencyCandidate.h"
#import "Util.h"

@implementation LowLatencyCandidate

@synthesize networkStream, remoteEndPoint;

+(LowLatencyCandidate*) lowLatencyCandidateToRemoteEndPoint:(id<NetworkEndPoint>)remoteEndPoint {
    
    ows_require(remoteEndPoint != nil);
    
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

-(TOCUntilOperation) tcpHandshakeCompleter {
    return ^(TOCCancelToken* untilCancelledToken) {
        return [self completer:untilCancelledToken];
    };
}

-(TOCFuture*) completer:(TOCCancelToken*)untilCancelledToken {
    TOCFuture* tcpHandshakeCompleted = [networkStream asyncTcpHandshakeCompleted];
    
    [untilCancelledToken whenCancelledTerminate:self];
    
    return [tcpHandshakeCompleted thenValue:self];
}

-(TOCFuture*) delayedUntilAuthenticated {
    return [networkStream.asyncConnectionCompleted thenValue:self];
}

@end
