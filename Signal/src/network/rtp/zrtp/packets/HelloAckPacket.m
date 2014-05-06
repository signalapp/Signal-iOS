#import "HelloAckPacket.h"

@implementation HelloAckPacket

+(HelloAckPacket*)helloAckPacket {
    HelloAckPacket* h = [HelloAckPacket new];
    h->embedding = [HandshakePacket handshakePacketWithTypeId:HANDSHAKE_TYPE_HELLO_ACK andPayload:[NSData data]];
    return h;
}

+(HelloAckPacket*)helloAckPacketParsedFromHandshakePacket:(HandshakePacket*)handshakePacket {
    checkOperation([[handshakePacket typeId] isEqualToData:HANDSHAKE_TYPE_HELLO_ACK]);
    checkOperation([[handshakePacket payload] length] == 0);
    
    HelloAckPacket* h = [HelloAckPacket new];
    h->embedding = handshakePacket;
    return h;
}

-(HandshakePacket*) embeddedIntoHandshakePacket {
    return embedding;
}

@end
