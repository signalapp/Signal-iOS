#import "CallConnectUtil_Server.h"

#import "CallConnectResult.h"
#import "DnsManager.h"
#import "IgnoredPacketFailure.h"
#import "LowLatencyConnector.h"
#import "SignalUtil.h"
#import "ZrtpManager.h"

#define BASE_TIMEOUT_SECONDS 1
#define RETRY_TIMEOUT_FACTOR 2
#define MAX_TRY_COUNT 5

@implementation CallConnectUtil_Server

+ (TOCFuture *)asyncConnectToDefaultSignalingServerUntilCancelled:(TOCCancelToken *)untilCancelledToken {
    return [self asyncConnectToSignalingServerAt:Environment.getSecureEndPointToDefaultRelayServer
                                  untilCancelled:untilCancelledToken];
}

+ (TOCFuture *)asyncConnectToSignalingServerNamed:(NSString *)name
                                   untilCancelled:(TOCCancelToken *)untilCancelledToken {
    ows_require(name != nil);
    return [self asyncConnectToSignalingServerAt:[Environment getSecureEndPointToSignalingServerNamed:name]
                                  untilCancelled:untilCancelledToken];
}

+ (TOCFuture *)asyncConnectToSignalingServerAt:(SecureEndPoint *)location
                                untilCancelled:(TOCCancelToken *)untilCancelledToken {
    ows_require(location != nil);

    TOCFuture *futureConnection =
        [LowLatencyConnector asyncLowLatencyConnectToEndPoint:location untilCancelled:untilCancelledToken];

    return [futureConnection thenTry:^(LowLatencyCandidate *result) {
      HttpSocket *httpSocket = [HttpSocket httpSocketOver:[result networkStream]];
      return [HttpManager httpManagerFor:httpSocket untilCancelled:untilCancelledToken];
    }];
}


+ (TOCFuture *)asyncConnectCallOverRelayDescribedInResponderSessionDescriptor:(ResponderSessionDescriptor *)session
                                                           withCallController:(CallController *)callController {
    ows_require(session != nil);
    ows_require(callController != nil);

    InitiatorSessionDescriptor *equivalentSession =
        [InitiatorSessionDescriptor initiatorSessionDescriptorWithSessionId:session.sessionId
                                                         andRelayServerName:session.relayServerName
                                                               andRelayPort:session.relayUdpPort];

    NSArray *interopOptions =
        session.interopVersion == 0
            ? @[ ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER ]
            : @[];
    if (session.interopVersion > 1)
        Environment.errorNoter(@"Newer-than-code interop version specified.", session, false);

    return [self asyncConnectCallOverRelayDescribedInInitiatorSessionDescriptor:equivalentSession
                                                             withCallController:callController
                                                              andInteropOptions:interopOptions];
}

+ (TOCFuture *)asyncConnectCallOverRelayDescribedInInitiatorSessionDescriptor:(InitiatorSessionDescriptor *)session
                                                           withCallController:(CallController *)callController
                                                            andInteropOptions:(NSArray *)interopOptions {
    ows_require(session != nil);
    ows_require(callController != nil);

    TOCFuture *futureUdpSocket =
        [self asyncRepeatedlyAttemptConnectToUdpRelayDescribedBy:session withCallController:callController];

    TOCFuture *futureZrtpHandshakeResult = [futureUdpSocket thenTry:^(UdpSocket *udpSocket) {
      return [ZrtpManager asyncPerformHandshakeOver:[RtpSocket rtpSocketOverUdp:udpSocket interopOptions:interopOptions]
                                  andCallController:callController];
    }];

    return [futureZrtpHandshakeResult thenTry:^(ZrtpHandshakeResult *zrtpResult) {
      AudioSocket *audioSocket = [AudioSocket audioSocketOver:[zrtpResult secureRtpSocket]];

      NSString *sas = [[zrtpResult masterSecret] shortAuthenticationString];

      return [CallConnectResult callConnectResultWithShortAuthenticationString:sas andAudioSocket:audioSocket];
    }];
}

+ (TOCFuture *)asyncRepeatedlyAttemptConnectToUdpRelayDescribedBy:(InitiatorSessionDescriptor *)sessionDescriptor
                                               withCallController:(CallController *)callController {
    ows_require(sessionDescriptor != nil);
    ows_require(callController != nil);

    TOCUntilOperation operation = ^(TOCCancelToken *internalUntilCancelledToken) {
      return [self asyncAttemptResolveThenConnectToUdpRelayDescribedBy:sessionDescriptor
                                                        untilCancelled:internalUntilCancelledToken
                                                      withErrorHandler:callController.errorHandler];
    };

    TOCFuture *futureRelayedUdpSocket = [TOCFuture retry:[TOCFuture operationTry:operation]
                                              upToNTimes:MAX_TRY_COUNT
                                         withBaseTimeout:BASE_TIMEOUT_SECONDS
                                          andRetryFactor:RETRY_TIMEOUT_FACTOR
                                          untilCancelled:[callController untilCancelledToken]];

    return [futureRelayedUdpSocket catchTry:^(id error) {
      return [TOCFuture
          futureWithFailure:[CallTermination callTerminationOfType:CallTerminationType_BadInteractionWithServer
                                                       withFailure:error
                                                    andMessageInfo:@"Timed out on all attempts to contact relay."]];
    }];
}

+ (TOCFuture *)asyncAttemptResolveThenConnectToUdpRelayDescribedBy:(InitiatorSessionDescriptor *)sessionDescriptor
                                                    untilCancelled:(TOCCancelToken *)untilCancelledToken
                                                  withErrorHandler:(ErrorHandlerBlock)errorHandler {
    ows_require(sessionDescriptor != nil);
    ows_require(errorHandler != nil);

    NSString *domain = [Environment relayServerNameToHostName:sessionDescriptor.relayServerName];

    TOCFuture *futureDnsResult =
        [DnsManager asyncQueryAddressesForDomainName:domain unlessCancelled:untilCancelledToken];

    TOCFuture *futureEndPoint = [futureDnsResult thenTry:^(NSArray *ipAddresses) {
      ows_require(ipAddresses.count > 0);

      IpAddress *address = ipAddresses[arc4random_uniform((unsigned int)ipAddresses.count)];
      return [IpEndPoint ipEndPointAtAddress:address onPort:sessionDescriptor.relayUdpPort];
    }];

    return [futureEndPoint thenTry:^(IpEndPoint *remote) {
      return [self asyncAttemptConnectToUdpRelayDescribedBy:remote
                                              withSessionId:sessionDescriptor.sessionId
                                             untilCancelled:untilCancelledToken
                                           withErrorHandler:errorHandler];
    }];
}

+ (TOCFuture *)asyncAttemptConnectToUdpRelayDescribedBy:(IpEndPoint *)remoteEndPoint
                                          withSessionId:(int64_t)sessionId
                                         untilCancelled:(TOCCancelToken *)untilCancelledToken
                                       withErrorHandler:(ErrorHandlerBlock)errorHandler {
    ows_require(remoteEndPoint != nil);
    ows_require(errorHandler != nil);

    UdpSocket *udpSocket = [UdpSocket udpSocketTo:remoteEndPoint];

    id<OccurrenceLogger> logger = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"relay setup"];

    TOCFuture *futureFirstResponseData = [self asyncFirstPacketReceivedAfterStartingSocket:udpSocket
                                                                            untilCancelled:untilCancelledToken
                                                                          withErrorHandler:errorHandler];

    TOCFuture *futureRelaySocket = [futureFirstResponseData thenTry:^id(NSData *openPortResponseData) {
      HttpResponse *openPortResponse = [HttpResponse httpResponseFromData:openPortResponseData];
      [logger markOccurrence:openPortResponse];
      if (!openPortResponse.isOkResponse)
          return [TOCFuture futureWithFailure:openPortResponse];

      return udpSocket;
    }];

    HttpRequest *openPortRequest = [HttpRequest httpRequestToOpenPortWithSessionId:sessionId];
    [logger markOccurrence:openPortRequest];
    [udpSocket send:[openPortRequest serialize]];

    return futureRelaySocket;
}

+ (TOCFuture *)asyncFirstPacketReceivedAfterStartingSocket:(UdpSocket *)udpSocket
                                            untilCancelled:(TOCCancelToken *)untilCancelledToken
                                          withErrorHandler:(ErrorHandlerBlock)errorHandler {
    ows_require(udpSocket != nil);
    ows_require(errorHandler != nil);

    TOCFutureSource *futureResultSource = [TOCFutureSource futureSourceUntil:untilCancelledToken];

    PacketHandlerBlock packetHandler = ^(id packet) {
      if (![futureResultSource trySetResult:packet]) {
          ;
          errorHandler([IgnoredPacketFailure
                           new:@"Received another packet before relay socket events redirected to new handler."],
                       packet,
                       false);
      }
    };

    ErrorHandlerBlock socketErrorHandler = ^(id error, id relatedInfo, bool causedTermination) {
      if (causedTermination)
          [futureResultSource trySetFailure:error];
      errorHandler(error, relatedInfo, causedTermination);
    };

    [udpSocket startWithHandler:[PacketHandler packetHandler:packetHandler withErrorHandler:socketErrorHandler]
                 untilCancelled:untilCancelledToken];

    return futureResultSource.future;
}

@end
