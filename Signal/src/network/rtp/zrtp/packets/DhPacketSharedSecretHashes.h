#import <Foundation/Foundation.h>

#define     DH_HASH_CHAIN_H0_LENGTH        32
#define     DH_HASH_CHAIN_H1_LENGTH        32
#define     DH_RS1_LENGTH                  8
#define     DH_RS2_LENGTH                  8
#define     DH_AUX_LENGTH                  8
#define     DH_PBX_LENGTH                  8

/**
 *
 * DhPacketSharedSecretHashes encapsulates values, related to the caching shared secrets, from DhPacket.
 *
 * We don't support caching shared secrets, so these values are only ever generated randomly (or parsed from one of the DH packets).
 *
**/

@interface DhPacketSharedSecretHashes : NSObject

@property (nonatomic,readonly) NSData* rs1;
@property (nonatomic,readonly) NSData* rs2;
@property (nonatomic,readonly) NSData* aux;
@property (nonatomic,readonly) NSData* pbx;

+(DhPacketSharedSecretHashes*) dhPacketSharedSecretHashesRandomized;

+(DhPacketSharedSecretHashes*) dhPacketSharedSecretHashesWithRs1:(NSData*)rs1
                                                          andRs2:(NSData*)rs2
                                                          andAux:(NSData*)aux
                                                          andPbx:(NSData*)pbx;

@end
