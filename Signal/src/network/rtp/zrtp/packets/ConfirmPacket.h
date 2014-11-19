#import <Foundation/Foundation.h>
#import "HandshakePacket.h"

/**
 * The Confirm1/Confirm2 packets sent by the initiator/responder to confirm that they know the shared secret.
 * The confirm_mac field is encrypted/authenticated using keys derived from the shared secret.
 *
 *  (extension header of RTP packet containing Confirm handshake packet)
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |0 1 0 1 0 0 0 0 0 1 0 1 1 0 1 0|         length=variable       |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |      Message Type Block="Confirm1" or "Confirm2" (2 words)    |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                     confirm_mac (2 words)                     |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                                                               |
 * |                CFB Initialization Vector (4 words)            |
 * |                                                               |
 * |                                                               |
 * +===============================================================+
 * |                                                               |
 * |                  Hash preimage H0 (8 words)                   |
 * |                             . . .                             |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * | Unused (15 bits of zeros)   | sig len (9 bits)|0 0 0 0|E|V|A|D|
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |              cache expiration interval (1 word)               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |      optional signature type block (1 word if present)        |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                                                               |
 * |           optional signature block (variable length)          |
 * |                            . . .                              |
 * |                                                               |
 * |                                                               |
 * +===============================================================+
 *
**/

@interface ConfirmPacket : NSObject

@property (strong, readonly, atomic) NSData* confirmMac;
@property (strong, readonly, atomic) NSData* iv;
@property (strong, readonly, atomic) NSData* hashChainH0;
@property (readonly, atomic) uint32_t unusedAndSignatureLengthAndFlags; // Unused (15 bits of zeros)   | sig len (9 bits)|0 0 0 0|E|V|A|D
@property (readonly, atomic) uint32_t cacheExperationInterval;
@property (readonly, atomic) bool isPartOne;

@property (strong, readonly, nonatomic, getter=embeddedIntoHandshakePacket) HandshakePacket* embedding;

+ (instancetype)packetOneWithHashChain:(HashChain*)hashChain
                             andMacKey:(NSData*)macKey
                          andCipherKey:(NSData*)cipherKey
                                 andIV:(NSData*)iv;

+ (instancetype)packetTwoWithHashChain:(HashChain*)hashChain
                             andMacKey:(NSData*)macKey
                          andCipherKey:(NSData*)cipherKey
                                 andIV:(NSData*)iv;

+ (instancetype)packetParsedFromHandshakePacket:(HandshakePacket*)handshakePacket
                                     withMacKey:(NSData*)macKey
                                   andCipherKey:(NSData*)cipherKey
                                   andIsPartOne:(bool)isPartOne;

@end
