#import "HttpRequest.h"
#import "HttpResponse.h"
#import "HttpSocket.h"
#import "Util.h"

@implementation HttpSocket

+(HttpSocket*) httpSocketOver:(NetworkStream*)rawDataChannel {
    ows_require(rawDataChannel != nil);
    
    HttpSocket* h = [HttpSocket new];
    h->rawDataChannelTcp = rawDataChannel;
    h->partialDataBuffer = [NSMutableData data];
    h->sentPacketsLogger = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"sent"];
    h->receivedPacketsLogger = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"received"];
    return h;
}
+(HttpSocket*) httpSocketOverUdp:(UdpSocket*)rawDataChannel {
    ows_require(rawDataChannel != nil);
    
    HttpSocket* h = [HttpSocket new];
    h->rawDataChannelUdp = rawDataChannel;
    h->partialDataBuffer = [NSMutableData data];
    h->sentPacketsLogger = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"sent"];
    h->receivedPacketsLogger = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"received"];
    return h;
}

-(void) sendHttpRequestOrResponse:(HttpRequestOrResponse*)requestOrResponse {
    ows_require(requestOrResponse != nil);
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
    ows_require(request != nil);
    [self sendHttpRequestOrResponse:[HttpRequestOrResponse httpRequestOrResponse:request]];
}
-(void) sendHttpResponse:(HttpResponse*)response {
    ows_require(response != nil);
    [self sendHttpRequestOrResponse:[HttpRequestOrResponse httpRequestOrResponse:response]];
}
-(void) send:(HttpRequestOrResponse*)packet {
    ows_require(packet != nil);
    [self sendHttpRequestOrResponse:packet];
}
-(void) startWithHandler:(PacketHandler*)handler
          untilCancelled:(TOCCancelToken*)untilCancelledToken {
    
    ows_require(handler != nil);
    requireState(httpSignalResponseHandler == nil);
    httpSignalResponseHandler = handler;
    
    TOCCancelTokenSource* lifetime = [TOCCancelTokenSource cancelTokenSourceUntil:untilCancelledToken];
    
    PacketHandler* packetHandler = [PacketHandler packetHandler:^(id packet) {
        ows_require(packet != nil);
        ows_require([packet isKindOfClass:NSData.class]);
        NSData* data = packet;
        
        [partialDataBuffer replaceBytesInRange:NSMakeRange(partialDataBuffer.length, data.length) withBytes:[data bytes]];
        
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
    } withErrorHandler:handler.errorHandler];
    
    if (rawDataChannelTcp != nil) {
        [rawDataChannelTcp startWithHandler:packetHandler];
        [lifetime.token whenCancelledTerminate:rawDataChannelTcp];
    } else {
        [rawDataChannelUdp startWithHandler:packetHandler
                             untilCancelled:lifetime.token];
    }
}

@end
