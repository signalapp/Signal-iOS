#import <Foundation/Foundation.h>
#import "SequenceCounter.h"
#import "RtpPacket.h"

/**
 *
 * SrtpStream is used by SrtpSocket to authenticate and cipher packets.
 * One SrtpStream is used for sending, and one is used for receiving.
 * (Because it's bad to use the same cryptographic keys in both directions.)
 *
**/

@interface SrtpStream : NSObject {
@private NSData* cipherKey;
@private NSData* cipherIvSalt;
@private NSData* macKey;
@private SequenceCounter* sequenceCounter;
}
+(SrtpStream*) srtpStreamWithCipherKey:(NSData*)cipherKey andMacKey:(NSData*)macKey andCipherIvSalt:(NSData*)cipherIvSalt;
-(RtpPacket*) encryptAndAuthenticateNormalRtpPacket:(RtpPacket*)normalRtpPacket;
-(RtpPacket*) verifyAuthenticationAndDecryptSecuredRtpPacket:(RtpPacket*)securedRtpPacket;
@end
