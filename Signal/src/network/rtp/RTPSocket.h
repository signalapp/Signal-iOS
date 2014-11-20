#import <Foundation/Foundation.h>
#import <CoreFoundation/CFSocket.h>
#include <sys/socket.h>
#include <netinet/in.h>
#import "UDPSocket.h"

#include "RTPPacket.h"
#import "PacketHandler.h"
#import "Terminable.h"

/**
 *
 * Rtp Socket is used to send RTP packets by serializing them over a UDPSocket.
 *
**/

@interface RTPSocket : NSObject

@property (strong, nonatomic) NSMutableArray* interopOptions;

- (instancetype)initOverUDPSocket:(UDPSocket*)udpSocket interopOptions:(NSArray*)interopOptions;
- (void)send:(RTPPacket*)packet;
- (void)startWithHandler:(PacketHandler*)handler untilCancelled:(TOCCancelToken*)untilCancelledToken;

@end
