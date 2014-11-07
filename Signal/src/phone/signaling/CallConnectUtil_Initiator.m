#import "CallConnectUtil_Initiator.h"
#import "CallConnectUtil.h"
#import "CallConnectUtil_Server.h"
#import "IgnoredPacketFailure.h"
#import "HttpRequest+SignalUtil.h"
#import "UnrecognizedRequestFailure.h"
#import "Util.h"
#import "ZrtpManager.h"

@implementation CallConnectUtil_Initiator

+ (TOCFuture*)asyncConnectCallToRemoteNumber:(PhoneNumber*)remoteNumber
                       withCallController:(CallController*)callController {
    
    require(remoteNumber != nil);
    require(callController != nil);
    require(callController.isInitiator);
    
    TOCFuture* futureInitiatorSessionDescriptor = [self asyncConnectToSignalServerAndGetInitiatorSessionDescriptorWithCallController:callController];
    
    return [futureInitiatorSessionDescriptor thenTry:^(InitiatorSessionDescriptor* session) {
        return [CallConnectUtil_Server asyncConnectCallOverRelayDescribedInInitiatorSessionDescriptor:session
                                                                                   withCallController:callController
                                                                                    andInteropOptions:@[]];
    }];
}

+ (TOCFuture*)asyncConnectToSignalServerAndGetInitiatorSessionDescriptorWithCallController:(CallController*)callController {
    require(callController != nil);
    
    TOCFuture* futureSignalConnection = [CallConnectUtil_Server asyncConnectToDefaultSignalingServerUntilCancelled:callController.untilCancelledToken];
    
    return [futureSignalConnection thenTry:^(HttpManager* httpManager) {
        requireState([httpManager isKindOfClass:[HttpManager class]]);
        
        TOCFutureSource* predeclaredFutureSession = [[TOCFutureSource alloc] init];
        
        HttpResponse* (^serverRequestHandler)(HttpRequest*) = ^(HttpRequest* remoteRequest) {
            return [self respondToServerRequest:remoteRequest
                        usingEventualDescriptor:predeclaredFutureSession.future
                              andCallController:callController];
        };
        
        [httpManager startWithRequestHandler:serverRequestHandler
                             andErrorHandler:callController.errorHandler
                              untilCancelled:[callController untilCancelledToken]];
        
        HttpRequest* initiateRequest = [HttpRequest httpRequestToInitiateToRemoteNumber:callController.callState.remoteNumber];
        TOCFuture* futureResponseToInitiate = [httpManager asyncOkResponseForRequest:initiateRequest
                                                                     unlessCancelled:[callController untilCancelledToken]];
        TOCFuture* futureResponseToInitiateWithInterpretedFailures = [futureResponseToInitiate catchTry:^(id error) {
            if ([error isKindOfClass:[HttpResponse class]]) {
                HttpResponse* badResponse = error;
                return [TOCFuture futureWithFailure:[self callTerminationForBadResponse:badResponse
                                                                      toInitiateRequest:initiateRequest]];
            }
            
            return [TOCFuture futureWithFailure:error];
        }];
        
        TOCFuture* futureSession = [futureResponseToInitiateWithInterpretedFailures thenTry:^(HttpResponse* response) {
            return [[InitiatorSessionDescriptor alloc] initFromJSON:response.getOptionalBodyText];
        }];
        [predeclaredFutureSession trySetResult:futureSession];
        
        return futureSession;
    }];
}

+ (CallTermination*)callTerminationForBadResponse:(HttpResponse*)badResponse
                                toInitiateRequest:(HttpRequest*)initiateRequest {
    require(badResponse != nil);
    require(initiateRequest != nil);
    
    switch (badResponse.getStatusCode) {
        case SIGNAL_STATUS_CODE_NO_SUCH_USER:
            return [[CallTermination alloc] initWithType:CallTerminationTypeNoSuchUser
                                              andFailure:badResponse
                                          andMessageInfo:initiateRequest];
        case SIGNAL_STATUS_CODE_SERVER_MESSAGE:
            return [[CallTermination alloc] initWithType:CallTerminationTypeServerMessage
                                              andFailure:badResponse
                                          andMessageInfo:badResponse.getOptionalBodyText];
        case SIGNAL_STATUS_CODE_LOGIN_FAILED:
            return [[CallTermination alloc] initWithType:CallTerminationTypeLoginFailed
                                              andFailure:badResponse
                                          andMessageInfo:initiateRequest];
        default:
            return [[CallTermination alloc] initWithType:CallTerminationTypeBadInteractionWithServer
                                              andFailure:badResponse
                                          andMessageInfo:initiateRequest];
    }
}

+ (HttpResponse*)respondToServerRequest:(HttpRequest*)request
                usingEventualDescriptor:(TOCFuture*)futureInitiatorSessionDescriptor
                      andCallController:(CallController*)callController {
    require(request != nil);
    require(futureInitiatorSessionDescriptor != nil);
    require(callController != nil);
    
    // heart beat?
    if (request.isKeepAlive) {
        return [HttpResponse httpResponse200Ok];
    }
    
    // too soon?
    if (!futureInitiatorSessionDescriptor.hasResult) {
        [callController terminateWithReason:CallTerminationTypeBadInteractionWithServer
                            withFailureInfo:[IgnoredPacketFailure new:@"Didn't receive session id from signaling server. Not able to understand request."]
                             andRelatedInfo:request];
        return [HttpResponse httpResponse500InternalServerError];
    }
    int64_t sessionId = [[futureInitiatorSessionDescriptor forceGetResult] sessionId];
    
    // hangup?
    if ([request isHangupForSession:sessionId]) {
        [callController terminateWithRejectionOrRemoteHangupAndFailureInfo:nil
                                                            andRelatedInfo:request];
        return [HttpResponse httpResponse200Ok];
    }
    
    // ringing?
    if ([request isRingingForSession:sessionId]) {
        [callController advanceCallProgressTo:CallProgressTypeRinging];
        return [HttpResponse httpResponse200Ok];
    }
    
    // busy signal?
    if ([request isBusyForSession:sessionId]) {
        [callController terminateWithReason:CallTerminationTypeResponderIsBusy
                            withFailureInfo:nil
                             andRelatedInfo:request];
        return [HttpResponse httpResponse200Ok];
    }
    
    // errr.....
    [callController terminateWithReason:CallTerminationTypeBadInteractionWithServer
                        withFailureInfo:[UnrecognizedRequestFailure new:@"Didn't understand signaling server."]
                         andRelatedInfo:request];
    return [HttpResponse httpResponse501NotImplemented];
}

@end
