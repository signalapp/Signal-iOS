#import "LowLatencyCandidate.h"
#import "Util.h"

@interface LowLatencyCandidate ()

@property (strong, readwrite, nonatomic) IPEndPoint* remoteEndPoint;
@property (strong, readwrite, nonatomic) NetworkStream* networkStream;

@end

@implementation LowLatencyCandidate

- (instancetype)initWithRemoteEndPoint:(id<NetworkEndPoint>)remoteEndPoint {
    if (self = [super init]) {
        require(remoteEndPoint != nil);
        
        self.remoteEndPoint = remoteEndPoint;
        self.networkStream = [[NetworkStream alloc] initWithRemoteEndPoint:remoteEndPoint];
    }
    
    return self;
}

- (void)terminate {
    [self.networkStream terminate];
}

- (void)preStart {
    [self.networkStream startProcessingStreamEventsEvenWithoutHandler];
}

- (TOCUntilOperation)tcpHandshakeCompleter {
    return ^(TOCCancelToken* untilCancelledToken) {
        return [self completer:untilCancelledToken];
    };
}

- (TOCFuture*)completer:(TOCCancelToken*)untilCancelledToken {
    TOCFuture* tcpHandshakeCompleted = [self.networkStream asyncTCPHandshakeCompleted];
    
    [untilCancelledToken whenCancelledTerminate:self];
    
    return [tcpHandshakeCompleted thenValue:self];
}

- (TOCFuture*)delayedUntilAuthenticated {
    return [self.networkStream.asyncConnectionCompleted thenValue:self];
}

@end
