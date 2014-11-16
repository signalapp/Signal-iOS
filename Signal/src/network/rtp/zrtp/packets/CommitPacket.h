#import "HandshakePacket.h"
#import "HashChain.h"
#import "ZID.h"
#import "HelloPacket.h"
#import "DHPacket.h"

/**
 * 
 * The Commit packet sent by the initiator to commit to their key agreement details without revealing them.
 * Specifies what crypto must be used by both sides.
 *
 *  (extension header of RTP packet containing Commit handshake packet)
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |0 1 0 1 0 0 0 0 0 1 0 1 1 0 1 0|        length=29 words        |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |              Message Type Block="Commit  " (2 words)          |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                                                               |
 * |                   Hash image H2 (8 words)                     |
 * |                             . . .                             |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                                                               |
 * |                         ZID  (3 words)                        |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                       hash algorithm                          |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                      cipher algorithm                         |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                       auth tag type                           |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                     Key Agreement Type                        |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                         SAS Type                              |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                                                               |
 * |                       hvi (8 words)                           |
 * |                           . . .                               |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                         MAC (2 words)                         |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *
**/

@interface CommitPacket : NSObject

@property (strong, readonly, nonatomic) NSData* h2;
@property (strong, readonly, nonatomic) NSData* hashSpecId;
@property (strong, readonly, nonatomic) NSData* cipherSpecId;
@property (strong, readonly, nonatomic) NSData* authSpecId;
@property (strong, readonly, nonatomic) NSData* agreementSpecId;
@property (strong, readonly, nonatomic) NSData* sasSpecId;
@property (strong, readonly, nonatomic) Zid* zid;
@property (strong, readonly, nonatomic) NSData* dhPart2HelloCommitment;

@property (strong, readonly, nonatomic, getter=embeddedIntoHandshakePacket) HandshakePacket* embedding;

- (instancetype)initFromHandshakePacket:(HandshakePacket*)handshakePacket;

+ (CommitPacket*)commitPacketWithDefaultSpecsAndKeyAgreementProtocol:(id<KeyAgreementProtocol>)keyAgreementProtocol
                                                        andHashChain:(HashChain*)hashChain
                                                              andZid:(Zid*)zid
                                                andCommitmentToHello:(HelloPacket*)hello
                                                          andDHPart2:(DHPacket*)dhPart2;

- (void)verifyCommitmentAgainstHello:(HelloPacket*)hello
                          andDHPart2:(DHPacket*)dhPart2;

- (void)verifyMacWithHashChainH1:(NSData*)hashChainH1;



@end
