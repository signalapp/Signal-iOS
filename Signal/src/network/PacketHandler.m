#import "PacketHandler.h"
#import "Constraints.h"

@implementation PacketHandler

@synthesize dataHandler, errorHandler;

+(PacketHandler*) packetHandler:(PacketHandlerBlock)dataHandler
               withErrorHandler:(ErrorHandlerBlock)errorHandler {
    
    ows_require(dataHandler != nil);
    ows_require(errorHandler != nil);
    
    PacketHandler* p = [PacketHandler new];
    p->dataHandler = [dataHandler copy];
    p->errorHandler = [errorHandler copy];
    return p;
}

-(void) handlePacket:(id)packet {
    dataHandler(packet);
}

-(void) handleError:(id)error
        relatedInfo:(id)relatedInfo
  causedTermination:(bool)causedTermination {
    
    DDLogError(@"Pack handler failed with error: %@ and info: %@", error, relatedInfo);
    errorHandler(error, relatedInfo, causedTermination);
}

@end
