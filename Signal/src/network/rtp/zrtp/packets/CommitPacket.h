#import "HandshakePacket.h"
#import "HashChain.h"
#import "ZID.h"
#import "HelloPacket.h"
#import "DhPacket.h"

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


@interface CommitPacket : NSObject {
@private HandshakePacket* embedding;
}
@property (nonatomic,readonly) NSData* h2;
@property (nonatomic,readonly) NSData* hashSpecId;
@property (nonatomic,readonly) NSData* cipherSpecId;
@property (nonatomic,readonly) NSData* authSpecId;
@property (nonatomic,readonly) NSData* agreementSpecId;
@property (nonatomic,readonly) NSData* sasSpecId;
@property (nonatomic,readonly) Zid* zid;
@property (nonatomic,readonly) NSData* dhPart2HelloCommitment;

+(CommitPacket*) commitPacketWithDefaultSpecsAndKeyAgreementProtocol:(id<KeyAgreementProtocol>)keyAgreementProtocol
                                                        andHashChain:(HashChain*)hashChain
                                                              andZid:(Zid*)zid
                                                andCommitmentToHello:(HelloPacket*)hello
                                                          andDhPart2:(DhPacket*)dhPart2;

+(CommitPacket*) commitPacketWithHashChainH2:(NSData*)h2
                                      andZid:(Zid*)zid
                               andHashSpecId:(NSData*)hashSpecId
                             andCipherSpecId:(NSData*)cipherSpecId
                               andAuthSpecId:(NSData*)authSpecId
                              andAgreeSpecId:(NSData*)agreeSpecId
                                andSasSpecId:(NSData*)sasSpecId
                   andDhPart2HelloCommitment:(NSData*)dhPart2HelloCommitment
                                  andHmacKey:(NSData*)hmacKey;

-(void) verifyCommitmentAgainstHello:(HelloPacket*)hello
                          andDhPart2:(DhPacket*)dhPart2;

+(CommitPacket*) commitPacketParsedFromHandshakePacket:(HandshakePacket*)handshakePacket;

-(void) verifyMacWithHashChainH1:(NSData*)hashChainH1;

-(HandshakePacket*) embeddedIntoHandshakePacket;

@end
