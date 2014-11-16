#import <Foundation/Foundation.h>
#import "CollapsingFutures.h"
#import "CyclicalBuffer.h"
#import "PacketHandler.h"
#import "NetworkEndPoint.h"
#import "Terminable.h"

@class SecureEndPoint;
@class HostNameEndPoint;
@class IPEndPoint;

/**
 *
 * The network stream class handles connecting to and communicating with a server over tcp or ssl.
 * To make an SSL connection, connect to a SecureEndPoint instead of a raw IPEndPoint or HostNameEndPoint.
 *
**/

@interface NetworkStream : NSObject <Terminable, NSStreamDelegate>

- (instancetype)initWithRemoteEndPoint:(id<NetworkEndPoint>)remoteEndPoint;

- (TOCFuture*)asyncConnectionCompleted;

- (TOCFuture*)asyncTCPHandshakeCompleted;

- (void)send:(NSData*)data;

- (void)startWithHandler:(PacketHandler*)handler;

- (void)startProcessingStreamEventsEvenWithoutHandler;

@end
