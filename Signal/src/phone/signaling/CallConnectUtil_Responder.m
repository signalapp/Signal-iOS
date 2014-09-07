#import "CallConnectUtil_Responder.h"

#import "CallConnectUtil.h"
#import "CallConnectUtil_Server.h"
#import "SignalUtil.h"
#import "UnrecognizedRequestFailure.h"
#import "Util.h"
#import "ZrtpManager.h"

@implementation CallConnectUtil_Responder

+(TOCFuture*) asyncConnectToIncomingCallWithSessionDescriptor:(ResponderSessionDescriptor*)sessionDescriptor
                                            andCallController:(CallController*)callController {
    
    require(sessionDescriptor != nil);
    require(callController != nil);
    require(!callController.isInitiator);
    
    TOCFuture* futureSignalsAreGo = [self asyncConnectToSignalServerDescribedBy:sessionDescriptor
                                                             withCallController:callController];
    
    TOCFuture* futureSignalsAreGoAndCallAccepted = [futureSignalsAreGo thenTry:^(id _) {
        [callController advanceCallProgressTo:CallProgressType_Ringing];
        
        return [callController interactiveCallAccepted];
    }];
    
    return [futureSignalsAreGoAndCallAccepted thenTry:^(id _) {
        return [CallConnectUtil_Server asyncConnectCallOverRelayDescribedInResponderSessionDescriptor:sessionDescriptor
                                                                                   withCallController:callController];
    }];
}

+(TOCFuture*) asyncConnectToSignalServerDescribedBy:(ResponderSessionDescriptor*)sessionDescriptor
                                 withCallController:(CallController*)callController {
    require(sessionDescriptor != nil);
    require(callController != nil);
    
    TOCFuture* futureSignalConnection = [CallConnectUtil_Server asyncConnectToSignalingServerNamed:sessionDescriptor.relayServerName
                                                                                    untilCancelled:[callController untilCancelledToken]];
    
    return [futureSignalConnection thenTry:^id(HttpManager* httpManager) {
        require([httpManager isKindOfClass:httpManager.class]);
        
        HttpResponse*(^serverRequestHandler)(HttpRequest*) = ^(HttpRequest* remoteRequest) {
            return [self respondToServerRequest:remoteRequest
                                usingDescriptor:sessionDescriptor
                              andCallController:callController];
        };
        
        [httpManager startWithRequestHandler:serverRequestHandler
                             andErrorHandler:Environment.errorNoter
                              untilCancelled:[callController untilCancelledToken]];
        
        HttpRequest* ringRequest = [HttpRequest httpRequestToRingWithSessionId:sessionDescriptor.sessionId];
        TOCFuture* futureResponseToRing = [httpManager asyncOkResponseForRequest:ringRequest
                                                                 unlessCancelled:[callController untilCancelledToken]];
        TOCFuture* futureResponseToRingWithInterpretedFailures = [futureResponseToRing catchTry:^(id error) {
            if ([error isKindOfClass:HttpResponse.class]) {
                HttpResponse* badResponse = error;
                return [TOCFuture futureWithFailure:[self callTerminationForBadResponse:badResponse
                                                                          toRingRequest:ringRequest]];
            }
            
            return [TOCFuture futureWithFailure:error];
        }];
        
        return [futureResponseToRingWithInterpretedFailures thenValue:@YES];
    }];
}

+(CallTermination*) callTerminationForBadResponse:(HttpResponse*)badResponse
                                    toRingRequest:(HttpRequest*)ringRequest {
    require(badResponse != nil);
    require(ringRequest != nil);
    
    switch (badResponse.getStatusCode) {
        case SIGNAL_STATUS_CODE_STALE_SESSION:
            return [CallTermination callTerminationOfType:CallTerminationType_StaleSession
                                              withFailure:badResponse
                                           andMessageInfo:ringRequest];
        case SIGNAL_STATUS_CODE_LOGIN_FAILED:
            return [CallTermination callTerminationOfType:CallTerminationType_LoginFailed
                                              withFailure:badResponse
                                           andMessageInfo:ringRequest];
        default:
            return [CallTermination callTerminationOfType:CallTerminationType_BadInteractionWithServer
                                              withFailure:badResponse
                                           andMessageInfo:ringRequest];
    }
}
+(HttpResponse*) respondToServerRequest:(HttpRequest*)request
                        usingDescriptor:(ResponderSessionDescriptor*)responderSessionDescriptor
                      andCallController:(CallController*)callController {
    require(request != nil);
    require(responderSessionDescriptor != nil);
    require(callController != nil);
    
    // heart beat?
    if (request.isKeepAlive) {
        return [HttpResponse httpResponse200Ok];
    }
    
    // hangup?
    if ([request isHangupForSession:responderSessionDescriptor.sessionId]) {
        [callController terminateWithReason:CallTerminationType_HangupRemote
                            withFailureInfo:nil
                             andRelatedInfo:request];
        return [HttpResponse httpResponse200Ok];
    }
    
    // errr......
    [callController terminateWithReason:CallTerminationType_BadInteractionWithServer
                        withFailureInfo:[UnrecognizedRequestFailure new:@"Didn't understand signaling server."]
                         andRelatedInfo:request];
    return [HttpResponse httpResponse501NotImplemented];
}

+(TOCFuture*) asyncSignalTooBusyToAnswerCallWithSessionDescriptor:(ResponderSessionDescriptor*)sessionDescriptor {
    require(sessionDescriptor != nil);
    
    HttpRequest* busyRequest = [HttpRequest httpRequestToSignalBusyWithSessionId:sessionDescriptor.sessionId];
    
    return [self asyncOkResponseFor:busyRequest
           fromSignalingServerNamed:sessionDescriptor.relayServerName
                    unlessCancelled:nil
                    andErrorHandler:Environment.errorNoter];
}

+(TOCFuture*) asyncOkResponseFor:(HttpRequest*)request
        fromSignalingServerNamed:(NSString*)name
                 unlessCancelled:(TOCCancelToken*)unlessCancelledToken
                 andErrorHandler:(ErrorHandlerBlock)errorHandler {
    require(request != nil);
    require(errorHandler != nil);
    require(name != nil);
    
    HttpManager* manager = [HttpManager startWithEndPoint:[Environment getSecureEndPointToSignalingServerNamed:name]
                                           untilCancelled:unlessCancelledToken];
    
    [manager startWithRejectingRequestHandlerAndErrorHandler:errorHandler
                                              untilCancelled:nil];
    
    TOCFuture* result = [manager asyncOkResponseForRequest:request
                                           unlessCancelled:unlessCancelledToken];
    
    [manager terminateWhenDoneCurrentWork];
    
    return result;
}

@end
