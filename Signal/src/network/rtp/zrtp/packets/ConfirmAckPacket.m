#import "ConfirmAckPacket.h"

@interface ConfirmAckPacket ()

@property (strong, readwrite, nonatomic, getter=embeddedIntoHandshakePacket) HandshakePacket* embedding;

@end

@implementation ConfirmAckPacket

- (instancetype)init {
    return [self initFromHandshakePacket:[[HandshakePacket alloc] initWithTypeId:HANDSHAKE_TYPE_CONFIRM_ACK
                                                                      andPayload:[[NSData alloc] init]]];
}

- (instancetype)initFromHandshakePacket:(HandshakePacket*)handshakePacket {
    if (self = [super init]) {
        checkOperation([[handshakePacket typeId] isEqualToData:HANDSHAKE_TYPE_CONFIRM_ACK]);
        checkOperation([[handshakePacket payload] length] == 0);
        
        self.embedding = handshakePacket;
    }
    
    return self;
}

@end
