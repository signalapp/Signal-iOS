#import <Foundation/Foundation.h>

typedef void (^PacketHandlerBlock)(id packet);
typedef void (^ErrorHandlerBlock)(id error, id relatedInfo, bool causedTermination);

/**
 *
 * A PacketHandler is a block to call for received values, and a block to call when minor or major error occur.
 *
 * Most of the socket types we use are started by giving them a packet handler.
 *
 **/

@interface PacketHandler : NSObject

@property (readonly,nonatomic) PacketHandlerBlock dataHandler;
@property (readonly,nonatomic) ErrorHandlerBlock errorHandler;

+(PacketHandler*) packetHandler:(PacketHandlerBlock)dataHandler
               withErrorHandler:(ErrorHandlerBlock)errorHandler;

-(void) handlePacket:(id)packet;

-(void) handleError:(id)error
        relatedInfo:(id)packet
  causedTermination:(bool)causedTermination;

@end
