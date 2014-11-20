#import "ConfirmAckPacket.h"

@interface ConfirmAckPacket ()

@property (strong, readwrite, nonatomic, getter=embeddedIntoHandshakePacket) HandshakePacket* embedding;

@end

@implementation ConfirmAckPacket

+ (instancetype)defaultPacket {
    return [[self alloc] initFromHandshakePacket:[[HandshakePacket alloc] initWithTypeId:HANDSHAKE_TYPE_CONFIRM_ACK
                                                                              andPayload:[[NSData alloc] init]]];
}

- (instancetype)initFromHandshakePacket:(HandshakePacket*)handshakePacket {
    self = [super init];
	
    if (self) {
        checkOperation([[handshakePacket typeId] isEqualToData:HANDSHAKE_TYPE_CONFIRM_ACK]);
        checkOperation([[handshakePacket payload] length] == 0);
        
        self.embedding = handshakePacket;
    }
    
    return self;
}

@end
