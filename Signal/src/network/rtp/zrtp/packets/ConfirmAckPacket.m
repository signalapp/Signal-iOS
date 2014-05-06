#import "ConfirmAckPacket.h"

@implementation ConfirmAckPacket

+(ConfirmAckPacket*)confirmAckPacket {
    ConfirmAckPacket* h = [ConfirmAckPacket new];
    h->embedding = [HandshakePacket handshakePacketWithTypeId:HANDSHAKE_TYPE_CONFIRM_ACK andPayload:[NSData data]];
    return h;
}

+(ConfirmAckPacket*)confirmAckPacketParsedFromHandshakePacket:(HandshakePacket*)handshakePacket {
    checkOperation([[handshakePacket typeId] isEqualToData:HANDSHAKE_TYPE_CONFIRM_ACK]);
    checkOperation([[handshakePacket payload] length] == 0);
    
    ConfirmAckPacket* h = [ConfirmAckPacket new];
    h->embedding = handshakePacket;
    return h;
}

-(HandshakePacket*) embeddedIntoHandshakePacket {
    return embedding;
}

@end
