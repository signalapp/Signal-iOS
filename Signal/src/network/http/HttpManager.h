#import <Foundation/Foundation.h>
#import "NetworkEndPoint.h"
#import "Logging.h"
#import "Terminable.h"
#import "Queue.h"
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
@private TOCCancelTokenSource* lifetime;
}

+(HttpManager*) httpManagerFor:(HttpSocket*)httpSocket
                untilCancelled:(TOCCancelToken*)untilCancelledToken;

+(HttpManager*) startWithEndPoint:(id<NetworkEndPoint>)endPoint
                   untilCancelled:(TOCCancelToken*)untilCancelledToken;

-(TOCFuture*) asyncResponseForRequest:(HttpRequest*)request
                      unlessCancelled:(TOCCancelToken*)unlessCancelledToken;

-(TOCFuture*) asyncOkResponseForRequest:(HttpRequest*)request
                        unlessCancelled:(TOCCancelToken*)unlessCancelledToken;

-(void) startWithRejectingRequestHandlerAndErrorHandler:(ErrorHandlerBlock)errorHandler
                                         untilCancelled:(TOCCancelToken*)untilCancelledToken;

-(void) startWithRequestHandler:(HttpResponse*(^)(HttpRequest* remoteRequest))requestHandler
                andErrorHandler:(ErrorHandlerBlock)errorHandler
                 untilCancelled:(TOCCancelToken*)untilCancelledToken;

-(void) terminateWhenDoneCurrentWork;

+(TOCFuture*) asyncOkResponseFromMasterServer:(HttpRequest*)request
                              unlessCancelled:(TOCCancelToken*)unlessCancelledToken
                              andErrorHandler:(ErrorHandlerBlock)errorHandler;

@end
