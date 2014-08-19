#import "HttpManager.h"
#import "FutureSource.h"
#import "NetworkStream.h"
#import "HttpSocket.h"
#import "Util.h"

@implementation HttpManager

+(HttpManager*) httpManagerFor:(HttpSocket*)httpSocket
                untilCancelled:(id<CancelToken>)untilCancelledToken {
    require(httpSocket != nil);
    
    HttpManager* m = [HttpManager new];
    m->httpChannel = httpSocket;
    m->eventualResponseQueue = [Queue new];
    m->lifetime = [CancelTokenSource cancelTokenSource];
    [untilCancelledToken whenCancelledTerminate:m];
    return m;
}
+(HttpManager*) startWithEndPoint:(id<NetworkEndPoint>)endPoint
                   untilCancelled:(id<CancelToken>)untilCancelledToken {
    require(endPoint != nil);
    
    NetworkStream* dataChannel = [NetworkStream networkStreamToEndPoint:endPoint];
    
    HttpSocket* httpChannel = [HttpSocket httpSocketOver:dataChannel];
    
    return [HttpManager httpManagerFor:httpChannel
                        untilCancelled:untilCancelledToken];
}
-(Future*) asyncResponseForRequest:(HttpRequest*)request
                   unlessCancelled:(id<CancelToken>)unlessCancelledToken {
    
    require(request != nil);
    requireState(isStarted);
    
    @try {
        FutureSource* ev = [FutureSource new];
        [unlessCancelledToken whenCancelledTryCancel:ev];
        @synchronized (self) {
            if ([[lifetime getToken] isAlreadyCancelled]) {
                return [Future failed:@"terminated"];
            }
            [eventualResponseQueue enqueue:ev];
        }
        [httpChannel send:[HttpRequestOrResponse httpRequestOrResponse:request]];
        return ev;
    } @catch (OperationFailed* ex) {
        return [Future failed:ex];
    }
}
+(Future*) asyncOkResponseFromMasterServer:(HttpRequest*)request
                           unlessCancelled:(id<CancelToken>)unlessCancelledToken
                           andErrorHandler:(ErrorHandlerBlock)errorHandler {
    require(request != nil);
    require(errorHandler != nil);
    
    HttpManager* manager = [HttpManager startWithEndPoint:[Environment getMasterServerSecureEndPoint]
                                           untilCancelled:unlessCancelledToken];
    
    [manager startWithRejectingRequestHandlerAndErrorHandler:errorHandler
                                              untilCancelled:nil];
    
    Future* result = [manager asyncOkResponseForRequest:request
                                        unlessCancelled:unlessCancelledToken];
    
    [manager terminateWhenDoneCurrentWork];
    
    return result;
}
-(Future*) asyncOkResponseForRequest:(HttpRequest*)request
                     unlessCancelled:(id<CancelToken>)unlessCancelledToken {
    
    require(request != nil);
    
    Future* futureResponse = [self asyncResponseForRequest:request
                                           unlessCancelled:unlessCancelledToken];
    
    return [futureResponse then:^(HttpResponse* response) {
        if (!response.isOkResponse) return [Future failed:response];
        return [Future finished:response];
    }];
}
-(void) startWithRejectingRequestHandlerAndErrorHandler:(ErrorHandlerBlock)errorHandler
                                         untilCancelled:(id<CancelToken>)untilCancelledToken {
    require(errorHandler != nil);
    
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
                 untilCancelled:(id<CancelToken>)untilCancelledToken {
    
    require(requestHandler != nil);
    require(errorHandler != nil);
    
    @synchronized(self) {
        requireState(!isStarted);
        isStarted = true;
    }
    
    ErrorHandlerBlock clearOnSeriousError = ^(id error, id relatedInfo, bool causedTermination) {
        if (causedTermination) [self clearQueue:error];
        errorHandler(error, relatedInfo, causedTermination);
    };
    
    PacketHandlerBlock httpHandler = ^(HttpRequestOrResponse* requestOrResponse) {
        require(requestOrResponse != nil);
        require([requestOrResponse isKindOfClass:[HttpRequestOrResponse class]]);
        @synchronized (self) {
            if (requestOrResponse.isRequest) {
                HttpResponse* response = requestHandler([requestOrResponse request]);
                requireState(response != nil);
                [httpChannel send:[HttpRequestOrResponse httpRequestOrResponse:response]];
            } else if (eventualResponseQueue.count == 0) {
                errorHandler(@"Response when no requests queued", [requestOrResponse response], false);
            } else {
                FutureSource* ev = [eventualResponseQueue dequeue];
                [ev trySetResult:[requestOrResponse response]];
            }
        }
    };
    
    [httpChannel startWithHandler:[PacketHandler packetHandler:httpHandler
                                              withErrorHandler:clearOnSeriousError]
                   untilCancelled:[lifetime getToken]];
    
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
            FutureSource* v = [eventualResponseQueue peekAt:eventualResponseQueue.count-1];
            [v finallyDo:^(id _) {
                [self terminate];
            }];
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
