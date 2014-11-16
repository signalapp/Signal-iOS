#import <Foundation/Foundation.h>
#import "SequenceCounter.h"
#import "RTPPacket.h"

/**
 *
 * SRTPStream is used by SRTPSocket to authenticate and cipher packets.
 * One SRTPStream is used for sending, and one is used for receiving.
 * (Because it's bad to use the same cryptographic keys in both directions.)
 *
**/

@interface SRTPStream : NSObject

- (instancetype)initWithCipherKey:(NSData*)cipherKey
                        andMacKey:(NSData*)macKey
                  andCipherIVSalt:(NSData*)cipherIVSalt;

-(RTPPacket*) encryptAndAuthenticateNormalRTPPacket:(RTPPacket*)normalRTPPacket;
-(RTPPacket*) verifyAuthenticationAndDecryptSecuredRTPPacket:(RTPPacket*)securedRTPPacket;

@end
