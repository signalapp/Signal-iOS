#import "HandshakePacket.h"
#import "HashChain.h"
#import "DHPacketSharedSecretHashes.h"

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

@interface DHPacket : NSObject

@property (readonly, nonatomic) bool isPart1;
@property (strong, readonly, nonatomic) DHPacketSharedSecretHashes* sharedSecretHashes;
@property (strong, readonly, nonatomic) NSData* publicKeyData;
@property (strong, readonly, nonatomic) NSData* hashChainH1;

@property (strong, readonly, nonatomic, getter=embeddedIntoHandshakePacket) HandshakePacket* embedding;

+ (DHPacket*)dh1PacketWithHashChain:(HashChain*)hashChain
              andSharedSecretHashes:(DHPacketSharedSecretHashes*)sharedSecretHashes
                       andKeyAgreer:(id<KeyAgreementParticipant>)agreer;

+ (DHPacket*)dh2PacketWithHashChain:(HashChain*)hashChain
              andSharedSecretHashes:(DHPacketSharedSecretHashes*)sharedSecretHashes
                       andKeyAgreer:(id<KeyAgreementParticipant>)agreer;

- (instancetype)initFromHandshakePacket:(HandshakePacket*)handshakePacket
                             andIsPart1:(bool)isPart1;

- (void)verifyMacWithHashChainH0:(NSData*)hashChainH0;

@end
