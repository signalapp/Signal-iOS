#import "HandshakePacket.h"
#import "HashChain.h"
#import "ZID.h"

/**
 *
 * The Hello packet sent by the initiator/responder to indicate what they are and which protocols they support.
 *
 *  (extension header of RTP packet containing Hello handshake packet)
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |0 1 0 1 0 0 0 0 0 1 0 1 1 0 1 0|             length            |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |            Message Type Block="Hello   " (2 words)            |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                   version="1.10" (1 word)                     |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                                                               |
 * |                Client Identifier (4 words)                    |
 * |                                                               |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                                                               |
 * |                   Hash image H3 (8 words)                     |
 * |                             . . .                             |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                                                               |
 * |                         ZID  (3 words)                        |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |0|S|M|P| unused (zeros)|  hc   |  cc   |  ac   |  kc   |  sc   |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                 hash algorithms (0 to 7 values)               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |               cipher algorithms (0 to 7 values)               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                  auth tag types (0 to 7 values)               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |               Key Agreement Types (0 to 7 values)             |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                    SAS Types (0 to 7 values)                  |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                         MAC (2 words)                         |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *
**/

@interface HelloPacket : NSObject

@property (strong, readonly, nonatomic) NSData* versionId;
@property (strong, readonly, nonatomic) NSData* clientId;
@property (strong, readonly, nonatomic) NSData* hashChainH3;
@property (strong, readonly, nonatomic) Zid* zid;
@property (readonly, nonatomic) uint8_t flags0SMP;
@property (readonly, nonatomic) uint8_t flagsUnusedLow4;
@property (readonly, nonatomic) uint8_t flagsUnusedHigh4;
@property (strong, readonly, nonatomic) NSArray* hashIds;
@property (strong, readonly, nonatomic) NSArray* cipherIds;
@property (strong, readonly, nonatomic) NSArray* authIds;
@property (strong, readonly, nonatomic) NSArray* agreeIds;
@property (strong, readonly, nonatomic) NSArray* sasIds;

@property (strong, readonly, nonatomic, getter=embeddedIntoHandshakePacket) HandshakePacket* embedding;

+ (HelloPacket*)helloPacketWithDefaultsAndHashChain:(HashChain*)hashChain
                                             andZid:(Zid*)zid
                           andKeyAgreementProtocols:(NSArray*)keyAgreementProtocols;

- (instancetype)initWithVersion:(NSData*)versionId
                    andClientId:(NSData*)clientId
                 andHashChainH3:(NSData*)hashChainH3
                         andZid:(Zid*)zid
                   andFlags0SMP:(uint8_t)flags0SMP
             andFlagsUnusedLow4:(uint8_t)flagsUnusedLow4
            andFlagsUnusedHigh4:(uint8_t)flagsUnusedHigh4
                 andHashSpecIds:(NSArray*)hashIds
               andCipherSpecIds:(NSArray*)cipherIds
                 andAuthSpecIds:(NSArray*)authIds
                andAgreeSpecIds:(NSArray*)agreeIds
                  andSasSpecIds:(NSArray*)sasIds
       authenticatedWithHMACKey:(NSData*)hmacKey;

- (instancetype)initFromHandshakePacket:(HandshakePacket*)handshakePacket;

- (void)verifyMacWithHashChainH2:(NSData*)hashChainH2;
- (NSArray*)agreeIdsIncludingImplied;

@end
