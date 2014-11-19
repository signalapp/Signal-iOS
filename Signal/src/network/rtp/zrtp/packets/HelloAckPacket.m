#import "HelloAckPacket.h"

@interface HelloAckPacket ()

@property (strong, readwrite, nonatomic, getter=embeddedIntoHandshakePacket) HandshakePacket* embedding;

@end

@implementation HelloAckPacket

+ (instancetype)defaultPacket {
    return [[self alloc] initFromHandshakePacket:[[HandshakePacket alloc] initWithTypeId:HANDSHAKE_TYPE_HELLO_ACK
                                                                              andPayload:[[NSData alloc] init]]];
}

- (instancetype)initFromHandshakePacket:(HandshakePacket*)handshakePacket {
    if (self = [super init]) {
        checkOperation([[handshakePacket typeId] isEqualToData:HANDSHAKE_TYPE_HELLO_ACK]);
        checkOperation([[handshakePacket payload] length] == 0);
        
        self.embedding = handshakePacket;
    }
    
    return self;
}

@end
