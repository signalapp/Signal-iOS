#import "HttpSocket.h"
#import "Constraints.h"
#import "HttpRequest.h"
#import "Util.h"
#import "HttpResponse.h"
#import "CancelTokenSource.h"

@implementation HttpSocket

+(HttpSocket*) httpSocketOver:(NetworkStream*)rawDataChannel {
    require(rawDataChannel != nil);
    
    HttpSocket* h = [HttpSocket new];
    h->rawDataChannelTcp = rawDataChannel;
    h->partialDataBuffer = [NSMutableData data];
    h->sentPacketsLogger = [[Environment logging] getOccurrenceLoggerForSender:self withKey:@"sent"];
    h->receivedPacketsLogger = [[Environment logging] getOccurrenceLoggerForSender:self withKey:@"received"];
    return h;
}
+(HttpSocket*) httpSocketOverUdp:(UdpSocket*)rawDataChannel {
    require(rawDataChannel != nil);
    
    HttpSocket* h = [HttpSocket new];
    h->rawDataChannelUdp = rawDataChannel;
    h->partialDataBuffer = [NSMutableData data];
    h->sentPacketsLogger = [[Environment logging] getOccurrenceLoggerForSender:self withKey:@"sent"];
    h->receivedPacketsLogger = [[Environment logging] getOccurrenceLoggerForSender:self withKey:@"received"];
    return h;
}

-(void) sendHttpRequestOrResponse:(HttpRequestOrResponse*)requestOrResponse {
    require(requestOrResponse != nil);
    requireState(httpSignalResponseHandler != nil);
    [sentPacketsLogger markOccurrence:requestOrResponse];
    NSData* data = [requestOrResponse serialize];
    if (rawDataChannelUdp != nil) {
        [rawDataChannelUdp send:data];
    } else {
        [rawDataChannelTcp send:data];
    }
}
-(void) sendHttpRequest:(HttpRequest*)request {
    require(request != nil);
    [self sendHttpRequestOrResponse:[HttpRequestOrResponse httpRequestOrResponse:request]];
}
-(void) sendHttpResponse:(HttpResponse*)response {
    require(response != nil);
    [self sendHttpRequestOrResponse:[HttpRequestOrResponse httpRequestOrResponse:response]];
}
-(void) send:(HttpRequestOrResponse*)packet {
    require(packet != nil);
    [self sendHttpRequestOrResponse:packet];
}
-(void) startWithHandler:(PacketHandler*)handler
          untilCancelled:(id<CancelToken>)untilCancelledToken {
    
    require(handler != nil);
    requireState(httpSignalResponseHandler == nil);
    httpSignalResponseHandler = handler;
    
    CancelTokenSource* lifetime = [CancelTokenSource cancelTokenSource];
    [untilCancelledToken whenCancelled:^{
        [lifetime cancel];
    }];
    
    PacketHandler* packetHandler = [PacketHandler packetHandler:^(id packet) {
        require(packet != nil);
        require([packet isKindOfClass:[NSData class]]);
        NSData* data = packet;
        
        [partialDataBuffer replaceBytesInRange:NSMakeRange([partialDataBuffer length], [data length]) withBytes:[data bytes]];
        
        while (true) {
            NSUInteger usedDataLength;
            HttpRequestOrResponse* s = nil;
            @try {
                s = [HttpRequestOrResponse tryExtractFromPartialData:partialDataBuffer usedLengthOut:&usedDataLength];
            } @catch (OperationFailed* error) {
                [handler handleError:error
                         relatedInfo:packet
                   causedTermination:true];
                [lifetime cancel];
                return;
            }
            if (s == nil) break;
            [partialDataBuffer replaceBytesInRange:NSMakeRange(0, usedDataLength) withBytes:NULL length:0];
            [receivedPacketsLogger markOccurrence:s];
            [handler handlePacket:s];
        }
    } withErrorHandler:[handler errorHandler]];
    
    if (rawDataChannelTcp != nil) {
        [rawDataChannelTcp startWithHandler:packetHandler];
        [[lifetime getToken] whenCancelledTerminate:rawDataChannelTcp];
    } else {
        [rawDataChannelUdp startWithHandler:packetHandler
                             untilCancelled:[lifetime getToken]];
    }
}

@end
