#import <Foundation/Foundation.h>
#import "NetworkEndPoint.h"
#import "Logging.h"
#import "Terminable.h"
#import "Queue.h"
#import "PacketHandler.h"
#import "HTTPSocket.h"

/**
 *
 * HTTPManager handles asynchronously performing and responding to http requests/responses.
 *
 */
@interface HTTPManager : NSObject <Terminable>

- (instancetype)initWithSocket:(HTTPSocket*)httpSocket
                untilCancelled:(TOCCancelToken*)untilCancelledToken;

- (instancetype)initWithEndPoint:(id<NetworkEndPoint>)endPoint
                  untilCancelled:(TOCCancelToken*)untilCancelledToken;

- (TOCFuture*)asyncResponseForRequest:(HTTPRequest*)request
                      unlessCancelled:(TOCCancelToken*)unlessCancelledToken;

- (TOCFuture*)asyncOkResponseForRequest:(HTTPRequest*)request
                        unlessCancelled:(TOCCancelToken*)unlessCancelledToken;

- (void)startWithRejectingRequestHandlerAndErrorHandler:(ErrorHandlerBlock)errorHandler
                                         untilCancelled:(TOCCancelToken*)untilCancelledToken;

- (void)startWithRequestHandler:(HTTPResponse*(^)(HTTPRequest* remoteRequest))requestHandler
                andErrorHandler:(ErrorHandlerBlock)errorHandler
                 untilCancelled:(TOCCancelToken*)untilCancelledToken;

- (void)terminateWhenDoneCurrentWork;

+ (TOCFuture*)asyncOkResponseFromMasterServer:(HTTPRequest*)request
                              unlessCancelled:(TOCCancelToken*)unlessCancelledToken
                              andErrorHandler:(ErrorHandlerBlock)errorHandler;

@end
