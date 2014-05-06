#import "HandshakePacket.h"
#import "HashChain.h"
#import "DhPacketSharedSecretHashes.h"

/**
 * The DHPart1/DHPart2 packets sent by responder/initiator to perform key agreement.
 * The 'pvr' field contains the public key data.
 *
 *  (extension header of RTP packet containing Diffie-Helman Key Exchange handshake packet)
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |0 1 0 1 0 0 0 0 0 1 0 1 1 0 1 0|   length=depends on KA Type   |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |     Message Type Block="DHPart1 " or "DHPart2 " (2 words)     |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                                                               |
 * |                   Hash image H1 (8 words)                     |
 * |                             . . .                             |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                        rs1IDr (2 words)                       |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                        rs2IDr (2 words)                       |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                     auxsecretIDr (2 words)                    |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                     pbxsecretIDr (2 words)                    |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                                                               |
 * |                  pvr (length depends on KA Type)              |
 * |                               . . .                           |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                         MAC (2 words)                         |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *
**/



@interface DhPacket : NSObject {
@private HandshakePacket* embedding;
}

@property (nonatomic,readonly) bool isPart1;
@property (nonatomic,readonly) DhPacketSharedSecretHashes* sharedSecretHashes;
@property (nonatomic,readonly) NSData* publicKeyData;
@property (nonatomic,readonly) NSData* hashChainH1;

+(DhPacket*) dh1PacketWithHashChain:(HashChain*)hashChain
              andSharedSecretHashes:(DhPacketSharedSecretHashes*)sharedSecretHashes
                       andKeyAgreer:(id<KeyAgreementParticipant>)agreer;

+(DhPacket*) dh2PacketWithHashChain:(HashChain*)hashChain
              andSharedSecretHashes:(DhPacketSharedSecretHashes*)sharedSecretHashes
                       andKeyAgreer:(id<KeyAgreementParticipant>)agreer;

+(DhPacket*) dhPacketWithHashChainH0:(NSData*)hashChainH0
               andSharedSecretHashes:(DhPacketSharedSecretHashes*)sharedSecretHashes
                    andPublicKeyData:(NSData*)publicKeyData
                          andIsPart1:(bool)isPart1;

+(DhPacket*) dhPacketFromHandshakePacket:(HandshakePacket*)handshakePacket
                              andIsPart1:(bool)isPart1;

-(void) verifyMacWithHashChainH0:(NSData*)hashChainH0;
-(HandshakePacket*) embeddedIntoHandshakePacket;

@end
