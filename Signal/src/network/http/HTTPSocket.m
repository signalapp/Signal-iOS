#import "HTTPRequest.h"
#import "HTTPResponse.h"
#import "HTTPSocket.h"
#import "Util.h"

@interface HTTPSocket ()

@property (strong, nonatomic) NetworkStream* rawDataChannelTCP;
@property (strong, nonatomic) UDPSocket* rawDataChannelUDP;

@property (strong, nonatomic) PacketHandler* httpSignalResponseHandler;
@property (strong, nonatomic) NSMutableData* partialDataBuffer;
@property (strong, nonatomic) id<OccurrenceLogger> sentPacketsLogger;
@property (strong, nonatomic) id<OccurrenceLogger> receivedPacketsLogger;

@end

@implementation HTTPSocket

- (instancetype)initOverNetworkStream:(NetworkStream*)rawDataChannel {
    if (self = [super init]) {
        require(rawDataChannel != nil);
        
        self.rawDataChannelTCP = rawDataChannel;
        self.partialDataBuffer = [[NSMutableData alloc] init];
        self.sentPacketsLogger = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"sent"];
        self.receivedPacketsLogger = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"received"];
    }
    
    return self;
}

- (instancetype)initOverUDP:(UDPSocket*)rawDataChannel {
    if (self = [super init]) {
        require(rawDataChannel != nil);
        
        self.rawDataChannelUDP = rawDataChannel;
        self.partialDataBuffer = [[NSMutableData alloc] init];
        self.sentPacketsLogger = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"sent"];
        self.receivedPacketsLogger =[Environment.logging getOccurrenceLoggerForSender:self withKey:@"received"];
    }
    
    return self;
}

- (void)sendHTTPRequestOrResponse:(HTTPRequestOrResponse*)requestOrResponse {
    require(requestOrResponse != nil);
    requireState(self.httpSignalResponseHandler != nil);
    [self.sentPacketsLogger markOccurrence:requestOrResponse];
    NSData* data = [requestOrResponse serialize];
    if (self.rawDataChannelUDP != nil) {
        [self.rawDataChannelUDP send:data];
    } else {
        [self.rawDataChannelTCP send:data];
    }
}

- (void)sendHTTPRequest:(HTTPRequest*)request {
    require(request != nil);
    [self sendHTTPRequestOrResponse:[[HTTPRequestOrResponse alloc] initWithRequestOrResponse:request]];
}

- (void)sendHTTPResponse:(HTTPResponse*)response {
    require(response != nil);
    [self sendHTTPRequestOrResponse:[[HTTPRequestOrResponse alloc] initWithRequestOrResponse:response]];
}

- (void)send:(HTTPRequestOrResponse*)packet {
    require(packet != nil);
    [self sendHTTPRequestOrResponse:packet];
}

- (void)startWithHandler:(PacketHandler*)handler
          untilCancelled:(TOCCancelToken*)untilCancelledToken {
    
    require(handler != nil);
    requireState(self.httpSignalResponseHandler == nil);
    self.httpSignalResponseHandler = handler;
    
    TOCCancelTokenSource* lifetime = [TOCCancelTokenSource cancelTokenSourceUntil:untilCancelledToken];
    
    PacketHandler* packetHandler = [[PacketHandler alloc] initPacketHandler:^(id packet) {
        require(packet != nil);
        require([packet isKindOfClass:NSData.class]);
        NSData* data = packet;
        
        [self.partialDataBuffer replaceBytesInRange:NSMakeRange(self.partialDataBuffer.length, data.length) withBytes:[data bytes]];
        
        while (true) {
            NSUInteger usedDataLength;
            HTTPRequestOrResponse* s = nil;
            @try {
                s = [HTTPRequestOrResponse tryExtractFromPartialData:self.partialDataBuffer usedLengthOut:&usedDataLength];
            } @catch (OperationFailed* error) {
                [handler handleError:error
                         relatedInfo:packet
                   causedTermination:true];
                [lifetime cancel];
                return;
            }
            if (s == nil) break;
            [self.partialDataBuffer replaceBytesInRange:NSMakeRange(0, usedDataLength) withBytes:NULL length:0];
            [self.receivedPacketsLogger markOccurrence:s];
            [handler handlePacket:s];
        }
    } withErrorHandler:handler.errorHandler];
    
    if (self.rawDataChannelTCP != nil) {
        [self.rawDataChannelTCP startWithHandler:packetHandler];
        [lifetime.token whenCancelledTerminate:self.rawDataChannelTCP];
    } else {
        [self.rawDataChannelUDP startWithHandler:packetHandler
                             untilCancelled:lifetime.token];
    }
}

@end
