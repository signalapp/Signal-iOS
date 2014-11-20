#import "RTPSocket.h"
#import "ThreadManager.h"
#import "Environment.h"

@interface RTPSocket ()

@property (strong, nonatomic) UDPSocket* udpSocket;
@property (strong, nonatomic) PacketHandler* currentHandler;
@property (strong, nonatomic) NSThread* currentHandlerThread;

@end

@implementation RTPSocket

- (instancetype)initOverUDPSocket:(UDPSocket*)udpSocket interopOptions:(NSArray*)interopOptions {
    if (self = [super init]) {
        require(udpSocket != nil);
        require(interopOptions != nil);
        
        self.udpSocket = udpSocket;
        self.interopOptions = [interopOptions mutableCopy];
    }
    
    return self;
}

- (void)startWithHandler:(PacketHandler*)handler untilCancelled:(TOCCancelToken*)untilCancelledToken {
    require(handler != nil);
    @synchronized(self) {
        bool isFirstTime = self.currentHandler == nil;
        self.currentHandler = handler;
        if (!isFirstTime) return;
    }
    
    PacketHandlerBlock valueHandler = ^(id packet) {
        require(packet != nil);
        require([packet isKindOfClass:[NSData class]]);
        NSData* data = packet;
        RTPPacket* rtpPacket = [[RTPPacket alloc] initFromPacketData:data];

        // enable interop when legacy client is detected
        if (rtpPacket.wasAdjustedDueToInteropIssues) {
            if ([Environment hasEnabledTestingOrLegacyOption:ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER]) {
                if (![self.interopOptions containsObject:ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER]) {
                    [self.interopOptions addObject:ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER];
                }
            }
        }
        
        [self handleRTPPacket:rtpPacket];
    };
    ErrorHandlerBlock errorHandler = ^(id error, id relatedInfo, bool causedTermination) {
        @synchronized(self) {
            self.currentHandler.errorHandler(error, relatedInfo, causedTermination);
        }
    };
    
    [self.udpSocket startWithHandler:[[PacketHandler alloc] initPacketHandler:valueHandler
                                                             withErrorHandler:errorHandler]
                      untilCancelled:untilCancelledToken];
}

- (void)handleRTPPacket:(RTPPacket*)rtpPacket {
    @synchronized(self) {
        if ([ThreadManager lowLatencyThread] == NSThread.currentThread) {
            [self.currentHandler handlePacket:rtpPacket];
            return;
        }
        
        [self performSelector:@selector(handleRTPPacket:)
                     onThread:[ThreadManager lowLatencyThread]
                   withObject:rtpPacket
                waitUntilDone:false];
    }
}

- (void)send:(RTPPacket*)packet {
    require(packet != nil);
    
    [self.udpSocket send:[packet rawPacketDataUsingInteropOptions:self.interopOptions]];
}

@end
