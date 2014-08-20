#import <Foundation/Foundation.h>
#import "CollapsingFutures.h"
#import "CyclicalBuffer.h"
#import "PacketHandler.h"
#import "NetworkEndPoint.h"
#import "Terminable.h"

@class SecureEndPoint;
@class HostNameEndPoint;
@class IpEndPoint;

/**
 *
 * The network stream class handles connecting to and communicating with a server over tcp or ssl.
 * To make an SSL connection, connect to a SecureEndPoint instead of a raw IpEndPoint or HostNameEndPoint.
 *
**/

@interface NetworkStream : NSObject<Terminable, NSStreamDelegate> {
@private NSMutableData* readBuffer;
@private NSInputStream* inputStream;
@private NSOutputStream* outputStream;
@private PacketHandler* rawDataHandler;
@private bool closedLocally;
@private CyclicalBuffer* writeBuffer;
@private TOCFutureSource* futureConnectedAndWritableSource;
@private TOCFutureSource* futureOpenedSource;
@private id<NetworkEndPoint> remoteEndPoint;
@private NSRunLoop* runLoop;
@private bool started;
}

+(NetworkStream*) networkStreamToEndPoint:(id<NetworkEndPoint>)remoteEndPoint;

-(TOCFuture*) asyncConnectionCompleted;

-(TOCFuture*) asyncTcpHandshakeCompleted;

-(void) send:(NSData*)data;

-(void) startWithHandler:(PacketHandler*)handler;

-(void) startProcessingStreamEventsEvenWithoutHandler;

@end
