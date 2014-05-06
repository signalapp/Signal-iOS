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

@interface ConfirmPacket : NSObject {
@private HandshakePacket* embedding;
}
@property (readonly,atomic) NSData* confirmMac;
@property (readonly,atomic) NSData* iv;
@property (readonly,atomic) NSData* hashChainH0;
@property (readonly,atomic) uint32_t unusedAndSignatureLengthAndFlags; // Unused (15 bits of zeros)   | sig len (9 bits)|0 0 0 0|E|V|A|D
@property (readonly,atomic) uint32_t cacheExperationInterval;
@property (readonly,atomic) bool isPart1;

+(ConfirmPacket*) confirm1PacketWithHashChain:(HashChain*)hashChain
                                    andMacKey:(NSData*)macKey
                                 andCipherKey:(NSData*)cipherKey
                                        andIv:(NSData*)iv;

+(ConfirmPacket*) confirm2PacketWithHashChain:(HashChain*)hashChain
                                    andMacKey:(NSData*)macKey
                                 andCipherKey:(NSData*)cipherKey
                                        andIv:(NSData*)iv;

+(ConfirmPacket*) confirmPacketWithHashChainH0:(NSData*)hashChainH0
           andUnusedAndSignatureLengthAndFlags:(uint32_t)unused
                    andCacheExpirationInterval:(uint32_t)cacheExpirationInterval
                                     andMacKey:(NSData*)macKey
                                  andCipherKey:(NSData*)cipherKey
                                         andIv:(NSData*)iv
                                    andIsPart1:(bool)isPart1;

+(ConfirmPacket*) confirmPacketParsedFromHandshakePacket:(HandshakePacket*)handshakePacket
                                              withMacKey:(NSData*)macKey
                                            andCipherKey:(NSData*)cipherKey
                                              andIsPart1:(bool)isPart1;

-(HandshakePacket*) embeddedIntoHandshakePacket;

@end
