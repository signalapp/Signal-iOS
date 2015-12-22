#import "HttpManager.h"
#import "Util.h"

@implementation HttpManager

+(HttpManager*) httpManagerFor:(HttpSocket*)httpSocket
                untilCancelled:(TOCCancelToken*)untilCancelledToken {
    ows_require(httpSocket != nil);
    
    HttpManager* m = [HttpManager new];
    m->httpChannel = httpSocket;
    m->eventualResponseQueue = [Queue new];
    m->lifetime = [TOCCancelTokenSource new];
    [untilCancelledToken whenCancelledTerminate:m];
    return m;
}
+(HttpManager*) startWithEndPoint:(id<NetworkEndPoint>)endPoint
                   untilCancelled:(TOCCancelToken*)untilCancelledToken {
    ows_require(endPoint != nil);
    
    NetworkStream* dataChannel = [NetworkStream networkStreamToEndPoint:endPoint];
    
    HttpSocket* httpChannel = [HttpSocket httpSocketOver:dataChannel];
    
    return [HttpManager httpManagerFor:httpChannel
                        untilCancelled:untilCancelledToken];
}
-(TOCFuture*) asyncResponseForRequest:(HttpRequest*)request
                      unlessCancelled:(TOCCancelToken*)unlessCancelledToken {
    
    ows_require(request != nil);
    requireState(isStarted);
    
    @try {
        TOCFutureSource* ev = [TOCFutureSource futureSourceUntil:unlessCancelledToken];
        @synchronized (self) {
            if (lifetime.token.isAlreadyCancelled) {
                return [TOCFuture futureWithFailure:@"terminated"];
            }
            [eventualResponseQueue enqueue:ev];
        }
        [httpChannel send:[HttpRequestOrResponse httpRequestOrResponse:request]];
        return ev.future;
    } @catch (OperationFailed* ex) {
        return [TOCFuture futureWithFailure:ex];
    }
}
+(TOCFuture*) asyncOkResponseFromMasterServer:(HttpRequest*)request
                              unlessCancelled:(TOCCancelToken*)unlessCancelledToken
                              andErrorHandler:(ErrorHandlerBlock)errorHandler {
    ows_require(request != nil);
    ows_require(errorHandler != nil);
    
    HttpManager* manager = [HttpManager startWithEndPoint:Environment.getMasterServerSecureEndPoint
                                           untilCancelled:unlessCancelledToken];
    
    [manager startWithRejectingRequestHandlerAndErrorHandler:errorHandler
                                              untilCancelled:nil];
    
    TOCFuture* result = [manager asyncOkResponseForRequest:request
                                           unlessCancelled:unlessCancelledToken];
    
    [manager terminateWhenDoneCurrentWork];
    
    return result;
}
-(TOCFuture*) asyncOkResponseForRequest:(HttpRequest*)request
                        unlessCancelled:(TOCCancelToken*)unlessCancelledToken {
    
    ows_require(request != nil);
    
    TOCFuture* futureResponse = [self asyncResponseForRequest:request
                                              unlessCancelled:unlessCancelledToken];
    
    return [futureResponse then:^id(HttpResponse* response) {
        if (!response.isOkResponse) return [TOCFuture futureWithFailure:response];
        return response;
    }];
}
-(void) startWithRejectingRequestHandlerAndErrorHandler:(ErrorHandlerBlock)errorHandler
                                         untilCancelled:(TOCCancelToken*)untilCancelledToken {
    ows_require(errorHandler != nil);
    
    HttpResponse*(^requestHandler)(HttpRequest* remoteRequest) = ^(HttpRequest* remoteRequest) {
        errorHandler(@"Rejecting Requests", remoteRequest, false);
        return [HttpResponse httpResponse501NotImplemented];
    };
    
    [self startWithRequestHandler:requestHandler
                  andErrorHandler:errorHandler
                   untilCancelled:untilCancelledToken];
}

-(void) startWithRequestHandler:(HttpResponse*(^)(HttpRequest* remoteRequest))requestHandler
                andErrorHandler:(ErrorHandlerBlock)errorHandler
                 untilCancelled:(TOCCancelToken*)untilCancelledToken {
    
    ows_require(requestHandler != nil);
    ows_require(errorHandler != nil);
    
    @synchronized(self) {
        requireState(!isStarted);
        isStarted = true;
    }
    
    ErrorHandlerBlock clearOnSeriousError = ^(id error, id relatedInfo, bool causedTermination) {
        if (causedTermination) [self clearQueue:error];
        errorHandler(error, relatedInfo, causedTermination);
    };
    
    PacketHandlerBlock httpHandler = ^(HttpRequestOrResponse* requestOrResponse) {
        ows_require(requestOrResponse != nil);
        ows_require([requestOrResponse isKindOfClass:HttpRequestOrResponse.class]);
        @synchronized (self) {
            if (requestOrResponse.isRequest) {
                HttpResponse* response = requestHandler([requestOrResponse request]);
                requireState(response != nil);
                [httpChannel send:[HttpRequestOrResponse httpRequestOrResponse:response]];
            } else if (eventualResponseQueue.count == 0) {
                errorHandler(@"Response when no requests queued", [requestOrResponse response], false);
            } else {
                TOCFutureSource* ev = [eventualResponseQueue dequeue];
                [ev trySetResult:requestOrResponse.response];
            }
        }
    };
    
    [httpChannel startWithHandler:[PacketHandler packetHandler:httpHandler
                                              withErrorHandler:clearOnSeriousError]
                   untilCancelled:lifetime.token];
    
    [untilCancelledToken whenCancelledTerminate:self];
}
-(void) clearQueue:(id)error {
    @synchronized (self) {
        while (eventualResponseQueue.count > 0) {
            [[eventualResponseQueue dequeue] trySetFailure:error];
        }
    }
}
-(void) terminateWhenDoneCurrentWork {
    @synchronized (self) {
        if (eventualResponseQueue.count == 0) {
            [self terminate];
        } else {
            TOCFutureSource* v = [eventualResponseQueue peekAt:eventualResponseQueue.count-1];
            [v.future.cancelledOnCompletionToken whenCancelledTerminate:self];
        }
    }
}
-(void) terminate {
    @synchronized (self) {
        [lifetime cancel];
        [self clearQueue:@"Terminated before response"];
    }
}

@end
