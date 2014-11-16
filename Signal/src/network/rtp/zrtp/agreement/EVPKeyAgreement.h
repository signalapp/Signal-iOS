#import <Foundation/Foundation.h>
#import "DH3KKeyAgreementProtocol.h"
#import "KeyAgreementParticipant.h"

@interface EVPKeyAgreement : NSObject

+ (EVPKeyAgreement*)evpDH3KKeyAgreementWithModulus:(NSData*)modulus andGenerator:(NSData*)generator;
+ (EVPKeyAgreement*)evpEC25KeyAgreement;

- (void)generateKeyPair;
- (NSData*)getPublicKey;
- (NSData*)getSharedSecretForRemotePublicKey:(NSData*)publicKey;

@end
