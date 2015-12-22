#import "RtpSocket.h"
#import "ThreadManager.h"
#import "Environment.h"

@implementation RtpSocket

+(RtpSocket*) rtpSocketOverUdp:(UdpSocket*)udpSocket interopOptions:(NSArray*)interopOptions {
    ows_require(udpSocket != nil);
    ows_require(interopOptions != nil);
    
    RtpSocket* s = [RtpSocket new];
    s->udpSocket = udpSocket;
    s->interopOptions = interopOptions.mutableCopy;
    return s;
}

-(void) startWithHandler:(PacketHandler*)handler untilCancelled:(TOCCancelToken*)untilCancelledToken {
    ows_require(handler != nil);
    @synchronized(self) {
        bool isFirstTime = currentHandler == nil;
        currentHandler = handler;
        if (!isFirstTime) return;
    }
    
    PacketHandlerBlock valueHandler = ^(id packet) {
        ows_require(packet != nil);
        ows_require([packet isKindOfClass:NSData.class]);
        NSData* data = packet;
        RtpPacket* rtpPacket = [RtpPacket rtpPacketParsedFromPacketData:data];

        // enable interop when legacy client is detected
        if (rtpPacket.wasAdjustedDueToInteropIssues) {
            if ([Environment hasEnabledTestingOrLegacyOption:ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER]) {
                if (![interopOptions containsObject:ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER]) {
                    [interopOptions addObject:ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER];
                }
            }
        }
        
        [self handleRtpPacket:rtpPacket];
    };
    ErrorHandlerBlock errorHandler = ^(id error, id relatedInfo, bool causedTermination) {
        @synchronized(self) {
            currentHandler.errorHandler(error, relatedInfo, causedTermination);
        }
    };
    
    [udpSocket startWithHandler:[PacketHandler packetHandler:valueHandler
                                            withErrorHandler:errorHandler]
                 untilCancelled:untilCancelledToken];
}
-(void) handleRtpPacket:(RtpPacket*)rtpPacket {
    @synchronized(self) {
        if ([ThreadManager lowLatencyThread] == NSThread.currentThread) {
            [currentHandler handlePacket:rtpPacket];
            return;
        }
        
        [self performSelector:@selector(handleRtpPacket:)
                     onThread:[ThreadManager lowLatencyThread]
                   withObject:rtpPacket
                waitUntilDone:false];
    }
}

-(void) send:(RtpPacket*)packet {
    ows_require(packet != nil);
    
    [udpSocket send:[packet rawPacketDataUsingInteropOptions:interopOptions]];
}

@end
