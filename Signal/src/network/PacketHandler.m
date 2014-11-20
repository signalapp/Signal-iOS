#import "PacketHandler.h"
#import "Constraints.h"

@interface PacketHandler ()

@property (strong, readwrite, nonatomic) PacketHandlerBlock dataHandler;
@property (strong, readwrite, nonatomic) ErrorHandlerBlock errorHandler;

@end

@implementation PacketHandler

- (instancetype)initPacketHandler:(PacketHandlerBlock)dataHandler
                 withErrorHandler:(ErrorHandlerBlock)errorHandler {
    self = [super init];
	
    if (self) {
        require(dataHandler != nil);
        require(errorHandler != nil);
        
        self.dataHandler = dataHandler;
        self.errorHandler = errorHandler;
    }
    
    return self;
}

- (void)handlePacket:(id)packet {
    self.dataHandler(packet);
}

- (void)handleError:(id)error
        relatedInfo:(id)relatedInfo
  causedTermination:(bool)causedTermination {
    
    DDLogError(@"Pack handler failed with error: %@ and info: %@", error, relatedInfo);
    self.errorHandler(error, relatedInfo, causedTermination);
}

@end
