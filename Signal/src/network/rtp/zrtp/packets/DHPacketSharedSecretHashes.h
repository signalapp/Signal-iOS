#import <Foundation/Foundation.h>

#define     DH_HASH_CHAIN_H0_LENGTH        32
#define     DH_HASH_CHAIN_H1_LENGTH        32
#define     DH_RS1_LENGTH                  8
#define     DH_RS2_LENGTH                  8
#define     DH_AUX_LENGTH                  8
#define     DH_PBX_LENGTH                  8

/**
 *
 * DHPacketSharedSecretHashes encapsulates values, related to the caching shared secrets, from DHPacket.
 *
 * We don't support caching shared secrets, so these values are only ever generated randomly (or parsed from one of the DH packets).
 *
**/

@interface DHPacketSharedSecretHashes : NSObject

@property (strong, readonly, nonatomic) NSData* rs1;
@property (strong, readonly, nonatomic) NSData* rs2;
@property (strong, readonly, nonatomic) NSData* aux;
@property (strong, readonly, nonatomic) NSData* pbx;

+ (DHPacketSharedSecretHashes*)randomized;

- (instancetype)initWithRs1:(NSData*)rs1
                     andRs2:(NSData*)rs2
                     andAux:(NSData*)aux
                     andPbx:(NSData*)pbx;

@end
