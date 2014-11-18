#import "HTTPManager.h"
#import "NetworkStream.h"
#import "HTTPSocket.h"
#import "Util.h"

@interface HTTPManager ()

@property (strong, nonatomic) HTTPSocket* httpChannel;
@property (strong, nonatomic) Queue* eventualResponseQueue;
@property (strong, nonatomic) TOCCancelTokenSource* lifetime;
@property (nonatomic) bool isStarted;

@end

@implementation HTTPManager

- (instancetype)initWithSocket:(HTTPSocket*)httpSocket
                untilCancelled:(TOCCancelToken*)untilCancelledToken {
    if (self = [super init]) {
        require(httpSocket != nil);
        
        self.httpChannel = httpSocket;
        self.eventualResponseQueue = [[Queue alloc] init];
        self.lifetime = [[TOCCancelTokenSource alloc] init];
        [untilCancelledToken whenCancelledTerminate:self];
    }
    
    return self;
}

- (instancetype)initWithEndPoint:(id<NetworkEndPoint>)endPoint
                  untilCancelled:(TOCCancelToken*)untilCancelledToken {
    require(endPoint != nil);
    
    NetworkStream* dataChannel = [[NetworkStream alloc] initWithRemoteEndPoint:endPoint];
    
    HTTPSocket* httpChannel = [[HTTPSocket alloc] initOverNetworkStream:dataChannel];
    
    return [self initWithSocket:httpChannel untilCancelled:untilCancelledToken];
}

- (TOCFuture*)asyncResponseForRequest:(HTTPRequest*)request
                      unlessCancelled:(TOCCancelToken*)unlessCancelledToken {
    
    require(request != nil);
    requireState(self.isStarted);
    
    @try {
        TOCFutureSource* ev = [TOCFutureSource futureSourceUntil:unlessCancelledToken];
        @synchronized (self) {
            if (self.lifetime.token.isAlreadyCancelled) {
                return [TOCFuture futureWithFailure:@"terminated"];
            }
            [self.eventualResponseQueue enqueue:ev];
        }
        [self.httpChannel send:[[HTTPRequestOrResponse alloc] initWithRequestOrResponse:request]];
        return ev.future;
    } @catch (OperationFailed* ex) {
        return [TOCFuture futureWithFailure:ex];
    }
}

+ (TOCFuture*)asyncOkResponseFromMasterServer:(HTTPRequest*)request
                              unlessCancelled:(TOCCancelToken*)unlessCancelledToken
                              andErrorHandler:(ErrorHandlerBlock)errorHandler {
    require(request != nil);
    require(errorHandler != nil);
    
    HTTPManager* manager = [[HTTPManager alloc] initWithEndPoint:Environment.getMasterServerSecureEndPoint
                                                  untilCancelled:unlessCancelledToken];
    
    [manager startWithRejectingRequestHandlerAndErrorHandler:errorHandler
                                              untilCancelled:nil];
    
    TOCFuture* result = [manager asyncOkResponseForRequest:request
                                           unlessCancelled:unlessCancelledToken];
    
    [manager terminateWhenDoneCurrentWork];
    
    return result;
}

- (TOCFuture*)asyncOkResponseForRequest:(HTTPRequest*)request
                        unlessCancelled:(TOCCancelToken*)unlessCancelledToken {
    
    require(request != nil);
    
    TOCFuture* futureResponse = [self asyncResponseForRequest:request
                                              unlessCancelled:unlessCancelledToken];
    
    return [futureResponse then:^id(HTTPResponse* response) {
        if (!response.isOkResponse) return [TOCFuture futureWithFailure:response];
        return response;
    }];
}

- (void)startWithRejectingRequestHandlerAndErrorHandler:(ErrorHandlerBlock)errorHandler
                                         untilCancelled:(TOCCancelToken*)untilCancelledToken {
    require(errorHandler != nil);
    
    HTTPResponse*(^requestHandler)(HTTPRequest* remoteRequest) = ^(HTTPRequest* remoteRequest) {
        errorHandler(@"Rejecting Requests", remoteRequest, false);
        return [HTTPResponse httpResponse501NotImplemented];
    };
    
    [self startWithRequestHandler:requestHandler
                  andErrorHandler:errorHandler
                   untilCancelled:untilCancelledToken];
}

- (void)startWithRequestHandler:(HTTPResponse*(^)(HTTPRequest* remoteRequest))requestHandler
                andErrorHandler:(ErrorHandlerBlock)errorHandler
                 untilCancelled:(TOCCancelToken*)untilCancelledToken {
    
    require(requestHandler != nil);
    require(errorHandler != nil);
    
    @synchronized(self) {
        requireState(!self.isStarted);
        self.isStarted = true;
    }
    
    ErrorHandlerBlock clearOnSeriousError = ^(id error, id relatedInfo, bool causedTermination) {
        if (causedTermination) [self clearQueue:error];
        errorHandler(error, relatedInfo, causedTermination);
    };
    
    PacketHandlerBlock httpHandler = ^(HTTPRequestOrResponse* requestOrResponse) {
        require(requestOrResponse != nil);
        require([requestOrResponse isKindOfClass:[HTTPRequestOrResponse class]]);
        @synchronized (self) {
            if (requestOrResponse.isRequest) {
                HTTPResponse* response = requestHandler([requestOrResponse request]);
                requireState(response != nil);
                [self.httpChannel send:[[HTTPRequestOrResponse alloc] initWithRequestOrResponse:response]];
            } else if (self.eventualResponseQueue.count == 0) {
                errorHandler(@"Response when no requests queued", [requestOrResponse response], false);
            } else {
                TOCFutureSource* ev = [self.eventualResponseQueue dequeue];
                [ev trySetResult:requestOrResponse.response];
            }
        }
    };
    
    [self.httpChannel startWithHandler:[[PacketHandler alloc] initPacketHandler:httpHandler
                                                               withErrorHandler:clearOnSeriousError]
                        untilCancelled:self.lifetime.token];
    
    [untilCancelledToken whenCancelledTerminate:self];
}

- (void)clearQueue:(id)error {
    @synchronized (self) {
        while (self.eventualResponseQueue.count > 0) {
            [[self.eventualResponseQueue dequeue] trySetFailure:error];
        }
    }
}

- (void)terminateWhenDoneCurrentWork {
    @synchronized (self) {
        if (self.eventualResponseQueue.count == 0) {
            [self terminate];
        } else {
            TOCFutureSource* v = [self.eventualResponseQueue peekAt:self.eventualResponseQueue.count-1];
            [v.future.cancelledOnCompletionToken whenCancelledTerminate:self];
        }
    }
}

- (void)terminate {
    @synchronized (self) {
        [self.lifetime cancel];
        [self clearQueue:@"Terminated before response"];
    }
}

@end
