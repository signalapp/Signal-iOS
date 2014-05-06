#import <Foundation/Foundation.h>

#define HASH_CHAIN_ITEM_LENGTH 32

/**
 *
 * HashChain's values are used in zrtp to prevent attackers from injecting packets after the handshake has started.
 * The values h0 through h3 are what you get by repeatedly hashing h0, so e.g. h2 = Sha256(h1).
 * The values in the chain are used, in reverse order, as the keys used to HMAC handshake packets.
 * Each value is sent to the other party only in packets after the packet that was authenticated with the value.
 * The idea is that attackers can't inject packets after the handshake starts, because finding satisfying hmac keys or hash pre-images is intractable.
 *
 * - Hellos contain h3, and are HMAC'ed with h2.
 * - Commit (from initiator only) contains h2, allowing verification of (the initiator's) Hello, and is HMAC'ed with h1.
 * - DHParts contain h1, allowing verification of (the initiator's) Commit, and are HMAC'ed with h0.
 * - Confirms contain h0, allowing verification of DHParts
 *
**/

@interface HashChain : NSObject

@property (nonatomic, readonly) NSData* h0;
@property (nonatomic, readonly) NSData* h1;
@property (nonatomic, readonly) NSData* h2;
@property (nonatomic, readonly) NSData* h3;

+(HashChain*) hashChainWithSeed:(NSData*)seed;
+(HashChain*) hashChainWithSecureGeneratedData;

@end
