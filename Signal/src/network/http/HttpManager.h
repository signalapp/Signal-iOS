#import <Foundation/Foundation.h>
#import "CancelTokenSource.h"
#import "NetworkEndPoint.h"
#import "Logging.h"
#import "Future.h"
#import "HttpRequestOrResponse.h"
#import "Terminable.h"
#import "Queue.h"
#import "CancelToken.h"
#import "PacketHandler.h"
#import "HttpSocket.h"

/**
 *
 * HttpManager handles asynchronously performing and responding to http requests/responses.
 *
 */
@interface HttpManager : NSObject<Terminable> {
@private HttpSocket* httpChannel;
@private Queue* eventualResponseQueue;
@private bool isStarted;
@private CancelTokenSource* lifetime;
}

+(HttpManager*) httpManagerFor:(HttpSocket*)httpSocket
                untilCancelled:(id<CancelToken>)untilCancelledToken;

+(HttpManager*) startWithEndPoint:(id<NetworkEndPoint>)endPoint
                   untilCancelled:(id<CancelToken>)untilCancelledToken;

-(Future*) asyncResponseForRequest:(HttpRequest*)request
                   unlessCancelled:(id<CancelToken>)unlessCancelledToken;

-(Future*) asyncOkResponseForRequest:(HttpRequest*)request
                     unlessCancelled:(id<CancelToken>)unlessCancelledToken;

-(void) startWithRejectingRequestHandlerAndErrorHandler:(ErrorHandlerBlock)errorHandler
                                         untilCancelled:(id<CancelToken>)untilCancelledToken;

-(void) startWithRequestHandler:(HttpResponse*(^)(HttpRequest* remoteRequest))requestHandler
                andErrorHandler:(ErrorHandlerBlock)errorHandler
                 untilCancelled:(id<CancelToken>)untilCancelledToken;

-(void) terminateWhenDoneCurrentWork;

+(Future*) asyncOkResponseFromMasterServer:(HttpRequest*)request
                           unlessCancelled:(id<CancelToken>)unlessCancelledToken
                           andErrorHandler:(ErrorHandlerBlock)errorHandler;

@end
