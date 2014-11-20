#import "CallConnectUtil_Server.h"
#import "AudioSocket.h"
#import "CallConnectResult.h"
#import "DNSManager.h"
#import "IgnoredPacketFailure.h"
#import "LowLatencyConnector.h"
#import "HTTPRequest+SignalUtil.h"
#import "UDPSocket.h"
#import "Util.h"
#import "ZRTPManager.h"

#define BASE_TIMEOUT_SECONDS 1
#define RETRY_TIMEOUT_FACTOR 2
#define MAX_TRY_COUNT 5

@implementation CallConnectUtil_Server

+ (TOCFuture*)asyncConnectToDefaultSignalingServerUntilCancelled:(TOCCancelToken*)untilCancelledToken {
    return [self asyncConnectToSignalingServerAt:Environment.getSecureEndPointToDefaultRelayServer
                                  untilCancelled:untilCancelledToken];
}

+ (TOCFuture*)asyncConnectToSignalingServerNamed:(NSString*)name
                                  untilCancelled:(TOCCancelToken*)untilCancelledToken {
    require(name != nil);
    return [self asyncConnectToSignalingServerAt:[Environment getSecureEndPointToSignalingServerNamed:name]
                                  untilCancelled:untilCancelledToken];
}

+ (TOCFuture*)asyncConnectToSignalingServerAt:(SecureEndPoint*)location
                               untilCancelled:(TOCCancelToken*)untilCancelledToken {
    require(location != nil);
    
    TOCFuture* futureConnection = [LowLatencyConnector asyncLowLatencyConnectToEndPoint:location
                                                                         untilCancelled:untilCancelledToken];
    
    return [futureConnection thenTry:^(LowLatencyCandidate* result) {
        HTTPSocket* httpSocket = [[HTTPSocket alloc] initOverNetworkStream:[result networkStream]];
        return [[HTTPManager alloc] initWithSocket:httpSocket untilCancelled:untilCancelledToken];
    }];
}


+ (TOCFuture*)asyncConnectCallOverRelayDescribedInResponderSessionDescriptor:(ResponderSessionDescriptor*)session
                                                          withCallController:(CallController*)callController {
    require(session != nil);
    require(callController != nil);
    
    InitiatorSessionDescriptor* equivalentSession = [[InitiatorSessionDescriptor alloc] initWithSessionId:session.sessionId
                                                                                       andRelayServerName:session.relayServerName
                                                                                             andRelayPort:session.relayUDPSocketPort];
    
    NSArray* interopOptions = session.interopVersion == 0
                            ? @[ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER]
                            : @[];
    if (session.interopVersion > 1) Environment.errorNoter(@"Newer-than-code interop version specified.", session, false);
    
    return [self asyncConnectCallOverRelayDescribedInInitiatorSessionDescriptor:equivalentSession
                                                             withCallController:callController
                                                              andInteropOptions:interopOptions];
}

+ (TOCFuture*)asyncConnectCallOverRelayDescribedInInitiatorSessionDescriptor:(InitiatorSessionDescriptor*)session
                                                          withCallController:(CallController*)callController
                                                           andInteropOptions:(NSArray*)interopOptions {
    require(session != nil);
    require(callController != nil);
    
    TOCFuture* futureUDPSocket = [self asyncRepeatedlyAttemptConnectToUDPSocketRelayDescribedBy:session
                                                                       withCallController:callController];
    
    TOCFuture* futureZRTPHandshakeResult = [futureUDPSocket thenTry:^(UDPSocket* udpSocket) {
        return [ZRTPManager asyncPerformHandshakeOver:[[RTPSocket alloc] initOverUDPSocket:udpSocket interopOptions:interopOptions]
                                    andCallController:callController];
    }];
    
    return [futureZRTPHandshakeResult thenTry:^(ZRTPHandshakeResult* zrtpResult) {
        AudioSocket* audioSocket = [[AudioSocket alloc] initOverSRTPSocket:zrtpResult.secureRTPSocket];
        
        NSString* sas = [zrtpResult.masterSecret shortAuthenticationString];
        
        return [[CallConnectResult alloc] initWithShortAuthenticationString:sas
                                                             andAudioSocket:audioSocket];
    }];
}

+ (TOCFuture*)asyncRepeatedlyAttemptConnectToUDPSocketRelayDescribedBy:(InitiatorSessionDescriptor*)sessionDescriptor
                                              withCallController:(CallController*)callController {
    
    require(sessionDescriptor != nil);
    require(callController != nil);
    
    TOCUntilOperation operation = ^(TOCCancelToken* internalUntilCancelledToken) {
        return [self asyncAttemptResolveThenConnectToUDPSocketRelayDescribedBy:sessionDescriptor
                                                          untilCancelled:internalUntilCancelledToken
                                                        withErrorHandler:callController.errorHandler];
    };
    
    TOCFuture* futureRelayedUDPSocket = [TOCFuture retry:[TOCFuture operationTry:operation]
                                              upToNTimes:MAX_TRY_COUNT
                                         withBaseTimeout:BASE_TIMEOUT_SECONDS
                                          andRetryFactor:RETRY_TIMEOUT_FACTOR
                                          untilCancelled:[callController untilCancelledToken]];
    
    return [futureRelayedUDPSocket catchTry:^(id error) {
        return [TOCFuture futureWithFailure:[[CallTermination alloc] initWithType:CallTerminationTypeBadInteractionWithServer
                                                                       andFailure:error
                                                                   andMessageInfo:@"Timed out on all attempts to contact relay."]];
    }];
}

+ (TOCFuture*)asyncAttemptResolveThenConnectToUDPSocketRelayDescribedBy:(InitiatorSessionDescriptor*)sessionDescriptor
                                                   untilCancelled:(TOCCancelToken*)untilCancelledToken
                                                 withErrorHandler:(ErrorHandlerBlock)errorHandler {
    
    require(sessionDescriptor != nil);
    require(errorHandler != nil);
    
    NSString* domain = [Environment relayServerNameToHostName:sessionDescriptor.relayServerName];
    
    TOCFuture* futureDnsResult = [DNSManager asyncQueryAddressesForDomainName:domain
                                                              unlessCancelled:untilCancelledToken];
    
    TOCFuture* futureEndPoint = [futureDnsResult thenTry:^(NSArray* ipAddresses) {
        require(ipAddresses.count > 0);
        
        IPAddress* address = ipAddresses[arc4random_uniform((unsigned int)ipAddresses.count)];
        return [[IPEndPoint alloc] initWithAddress:address
                                            onPort:sessionDescriptor.relayUDPSocketPort];
    }];
    
    return [futureEndPoint thenTry:^(IPEndPoint* remote) {
        return [self asyncAttemptConnectToUDPSocketRelayDescribedBy:remote
                                                withSessionId:sessionDescriptor.sessionId
                                               untilCancelled:untilCancelledToken
                                             withErrorHandler:errorHandler];
    }];
}

+ (TOCFuture*)asyncAttemptConnectToUDPSocketRelayDescribedBy:(IPEndPoint*)remoteEndPoint
                                         withSessionId:(int64_t)sessionId
                                        untilCancelled:(TOCCancelToken*)untilCancelledToken
                                      withErrorHandler:(ErrorHandlerBlock)errorHandler {
    
    require(remoteEndPoint != nil);
    require(errorHandler != nil);
    
    UDPSocket* udpSocket = [[UDPSocket alloc] initSocketToRemoteEndPoint:remoteEndPoint];
    
    id<OccurrenceLogger> logger = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"relay setup"];
    
    TOCFuture* futureFirstResponseData = [self asyncFirstPacketReceivedAfterStartingSocket:udpSocket
                                                                            untilCancelled:untilCancelledToken
                                                                          withErrorHandler:errorHandler];
    
    TOCFuture* futureRelaySocket = [futureFirstResponseData thenTry:^id(NSData* openPortResponseData) {
        HTTPResponse* openPortResponse = [HTTPResponse httpResponseFromData:openPortResponseData];
        [logger markOccurrence:openPortResponse];
        if (!openPortResponse.isOkResponse) return [TOCFuture futureWithFailure:openPortResponse];
        
        return udpSocket;
    }];
    
    HTTPRequest* openPortRequest = [HTTPRequest httpRequestToOpenPortWithSessionId:sessionId];
    [logger markOccurrence:openPortRequest];
    [udpSocket send:[openPortRequest serialize]];
    
    return futureRelaySocket;
}

+ (TOCFuture*)asyncFirstPacketReceivedAfterStartingSocket:(UDPSocket*)udpSocket
                                           untilCancelled:(TOCCancelToken*)untilCancelledToken
                                         withErrorHandler:(ErrorHandlerBlock)errorHandler {
    
    require(udpSocket != nil);
    require(errorHandler != nil);
    
    TOCFutureSource* futureResultSource = [TOCFutureSource futureSourceUntil:untilCancelledToken];
    
    PacketHandlerBlock packetHandler = ^(id packet) {
        if (![futureResultSource trySetResult:packet]) {;
            errorHandler([[IgnoredPacketFailure alloc] initWithReason:@"Received another packet before relay socket events redirected to new handler."], packet, false);
        }
    };
    
    ErrorHandlerBlock socketErrorHandler = ^(id error, id relatedInfo, bool causedTermination) {
        if (causedTermination) [futureResultSource trySetFailure:error];
        errorHandler(error, relatedInfo, causedTermination);
    };
    
    [udpSocket startWithHandler:[[PacketHandler alloc] initPacketHandler:packetHandler
                                                        withErrorHandler:socketErrorHandler]
                 untilCancelled:untilCancelledToken];
    
    return futureResultSource.future;
}

@end
