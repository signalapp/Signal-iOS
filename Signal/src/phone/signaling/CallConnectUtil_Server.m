#import "CallConnectUtil_Server.h"

#import "AudioSocket.h"
#import "CallConnectResult.h"
#import "DnsManager.h"
#import "IgnoredPacketFailure.h"
#import "LowLatencyConnector.h"
#import "SignalUtil.h"
#import "UdpSocket.h"
#import "Util.h"
#import "ZrtpManager.h"

#define BASE_TIMEOUT_SECONDS 1
#define RETRY_TIMEOUT_FACTOR 2
#define MAX_TRY_COUNT 5

@implementation CallConnectUtil_Server

+(Future*) asyncConnectToDefaultSignalingServerUntilCancelled:(id<CancelToken>)untilCancelledToken {
    return [self asyncConnectToSignalingServerAt:[Environment getSecureEndPointToDefaultRelayServer]
                                  untilCancelled:untilCancelledToken];
}

+(Future*) asyncConnectToSignalingServerNamed:(NSString*)name
                               untilCancelled:(id<CancelToken>)untilCancelledToken {
    require(name != nil);
    return [self asyncConnectToSignalingServerAt:[Environment getSecureEndPointToSignalingServerNamed:name]
                                  untilCancelled:untilCancelledToken];
}

+(Future*) asyncConnectToSignalingServerAt:(SecureEndPoint*)location
                            untilCancelled:(id<CancelToken>)untilCancelledToken {
    require(location != nil);
    
    Future* futureConnection = [LowLatencyConnector asyncLowLatencyConnectToEndPoint:location
                                                                      untilCancelled:untilCancelledToken];
    
    return [futureConnection then:^(LowLatencyCandidate* result) {
        HttpSocket* httpSocket = [HttpSocket httpSocketOver:[result networkStream]];
        return [HttpManager httpManagerFor:httpSocket
                            untilCancelled:untilCancelledToken];
    }];
}


+(Future*) asyncConnectCallOverRelayDescribedInResponderSessionDescriptor:(ResponderSessionDescriptor*)session
                                                       withCallController:(CallController*)callController {
    require(session != nil);
    require(callController != nil);
    
    InitiatorSessionDescriptor* equivalentSession = [InitiatorSessionDescriptor initiatorSessionDescriptorWithSessionId:session.sessionId
                                                                                                     andRelayServerName:session.relayServerName
                                                                                                           andRelayPort:session.relayUdpPort];

    NSArray* interopOptions = session.interopVersion == 0
                            ? @[ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER]
                            : @[];
    if (session.interopVersion > 1) [Environment errorNoter](@"Newer-than-code interop version specified.", session, false);
    
    return [self asyncConnectCallOverRelayDescribedInInitiatorSessionDescriptor:equivalentSession
                                                             withCallController:callController
                                                              andInteropOptions:interopOptions];
}

+(Future*) asyncConnectCallOverRelayDescribedInInitiatorSessionDescriptor:(InitiatorSessionDescriptor*)session
                                                       withCallController:(CallController*)callController
                                                        andInteropOptions:(NSArray*)interopOptions {
    require(session != nil);
    require(callController != nil);
    
    Future* futureUdpSocket = [self asyncRepeatedlyAttemptConnectToUdpRelayDescribedBy:session
                                                                    withCallController:callController];
    
    Future* futureZrtpHandshakeResult = [futureUdpSocket then:^(UdpSocket* udpSocket) {
        return [ZrtpManager asyncPerformHandshakeOver:[RtpSocket rtpSocketOverUdp:udpSocket interopOptions:interopOptions]
                                    andCallController:callController];
    }];
    
    return [futureZrtpHandshakeResult then:^(ZrtpHandshakeResult* zrtpResult) {
        AudioSocket* audioSocket = [AudioSocket audioSocketOver:[zrtpResult secureRtpSocket]];
        
        NSString* sas = [[zrtpResult masterSecret] shortAuthenticationString];
        
        return [CallConnectResult callConnectResultWithShortAuthenticationString:sas
                                                                  andAudioSocket:audioSocket];
    }];
}

+(Future*) asyncRepeatedlyAttemptConnectToUdpRelayDescribedBy:(InitiatorSessionDescriptor*)sessionDescriptor
                                           withCallController:(CallController*)callController {
    
    require(sessionDescriptor != nil);
    require(callController != nil);
    
    CancellableOperationStarter operation = ^(id<CancelToken> internalUntilCancelledToken) {
        return [self asyncAttemptResolveThenConnectToUdpRelayDescribedBy:sessionDescriptor
                                                          untilCancelled:internalUntilCancelledToken
                                                        withErrorHandler:[callController errorHandler]];
    };
    
    Future* futureRelayedUdpSocket = [AsyncUtil asyncTry:operation
                                              upToNTimes:MAX_TRY_COUNT
                                         withBaseTimeout:BASE_TIMEOUT_SECONDS
                                          andRetryFactor:RETRY_TIMEOUT_FACTOR
                                          untilCancelled:[callController untilCancelledToken]];
    
    return [futureRelayedUdpSocket catch:^(id error) {
        return [Future failed:[CallTermination callTerminationOfType:CallTerminationType_BadInteractionWithServer
                                                         withFailure:error
                                                      andMessageInfo:@"Timed out on all attempts to contact relay."]];
    }];
}

+(Future*) asyncAttemptResolveThenConnectToUdpRelayDescribedBy:(InitiatorSessionDescriptor*)sessionDescriptor
                                                untilCancelled:(id<CancelToken>)untilCancelledToken
                                              withErrorHandler:(ErrorHandlerBlock)errorHandler {
    
    require(sessionDescriptor != nil);
    require(errorHandler != nil);
    
    NSString* domain = [Environment relayServerNameToHostName:[sessionDescriptor relayServerName]];
    
    Future* futureDnsResult = [DnsManager asyncQueryAddressesForDomainName:domain
                                                           unlessCancelled:untilCancelledToken];
    
    Future* futureEndPoint = [futureDnsResult then:^(NSArray* ipAddresses) {
        require(ipAddresses.count > 0);
        
        IpAddress* address = ipAddresses[arc4random_uniform((unsigned int)ipAddresses.count)];
        return [IpEndPoint ipEndPointAtAddress:address
                                        onPort:sessionDescriptor.relayUdpPort];
    }];
    
    return [futureEndPoint then:^(IpEndPoint* remote) {
        return [self asyncAttemptConnectToUdpRelayDescribedBy:remote
                                                 withSessionId:sessionDescriptor.sessionId
                                               untilCancelled:untilCancelledToken
                                             withErrorHandler:errorHandler];
    }];
}

+(Future*) asyncAttemptConnectToUdpRelayDescribedBy:(IpEndPoint*)remoteEndPoint
                                      withSessionId:(int64_t)sessionId
                                     untilCancelled:(id<CancelToken>)untilCancelledToken
                                   withErrorHandler:(ErrorHandlerBlock)errorHandler {
    
    require(remoteEndPoint != nil);
    require(errorHandler != nil);
    
    UdpSocket* udpSocket = [UdpSocket udpSocketTo:remoteEndPoint];
    
    id<OccurrenceLogger> logger = [[Environment logging] getOccurrenceLoggerForSender:self withKey:@"relay setup"];
    
    Future* futureFirstResponseData = [self asyncFirstPacketReceivedAfterStartingSocket:udpSocket
                                                                         untilCancelled:untilCancelledToken
                                                                       withErrorHandler:errorHandler];
    
    Future* futureRelaySocket = [futureFirstResponseData then:^id(NSData* openPortResponseData) {
        HttpResponse* openPortResponse = [HttpResponse httpResponseFromData:openPortResponseData];
        [logger markOccurrence:openPortResponse];
        if (![openPortResponse isOkResponse]) return [Future failed:openPortResponse];
        
        return udpSocket;
    }];
    
    HttpRequest* openPortRequest = [HttpRequest httpRequestToOpenPortWithSessionId:sessionId];
    [logger markOccurrence:openPortRequest];
    [udpSocket send:[openPortRequest serialize]];
    
    return futureRelaySocket;
}

+(Future*) asyncFirstPacketReceivedAfterStartingSocket:(UdpSocket*)udpSocket
                                        untilCancelled:(id<CancelToken>)untilCancelledToken
                                      withErrorHandler:(ErrorHandlerBlock)errorHandler {
    
    require(udpSocket != nil);
    require(errorHandler != nil);
    
    FutureSource* futureResultSource = [FutureSource new];
    
    [untilCancelledToken whenCancelledTryCancel:futureResultSource];
    
    PacketHandlerBlock packetHandler = ^(id packet) {
        if (![futureResultSource trySetResult:packet]) {;
            errorHandler([IgnoredPacketFailure new:@"Received another packet before relay socket events redirected to new handler."], packet, false);
        }
    };
    
    ErrorHandlerBlock socketErrorHandler = ^(id error, id relatedInfo, bool causedTermination) {
        if (causedTermination) [futureResultSource trySetFailure:error];
        errorHandler(error, relatedInfo, causedTermination);
    };
    
    [udpSocket startWithHandler:[PacketHandler packetHandler:packetHandler
                                            withErrorHandler:socketErrorHandler]
                 untilCancelled:untilCancelledToken];
    
    return futureResultSource;
}

@end
