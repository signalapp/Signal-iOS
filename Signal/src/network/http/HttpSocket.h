#import <Foundation/Foundation.h>
#import "PacketHandler.h"
#import "HttpRequestOrResponse.h"
#import "HttpResponse.h"
#import "UdpSocket.h"
#import "NetworkStream.h"
#import "Environment.h"

/**
 *
 * HttpSocket is responsible for communicating Http requests and responses over some data channel (tcp, ssl, udp, whatever).
 *
 */
@interface HttpSocket : NSObject {
@private NetworkStream* rawDataChannelTcp;
@private UdpSocket* rawDataChannelUdp;
    
@private PacketHandler* httpSignalResponseHandler;
@private NSMutableData* partialDataBuffer;
@private id<OccurrenceLogger> sentPacketsLogger;
@private id<OccurrenceLogger> receivedPacketsLogger;
}

+(HttpSocket*) httpSocketOver:(NetworkStream*)rawDataChannel;
+(HttpSocket*) httpSocketOverUdp:(UdpSocket*)rawDataChannel;
-(void) sendHttpRequest:(HttpRequest*)request;
-(void) sendHttpResponse:(HttpResponse*)response;
-(void) send:(HttpRequestOrResponse*)packet;
-(void) startWithHandler:(PacketHandler*)handler
          untilCancelled:(TOCCancelToken*)untilCancelledToken;

@end
