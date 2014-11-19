#import <Foundation/Foundation.h>
#import "DH3KKeyAgreementProtocol.h"
#import "KeyAgreementParticipant.h"

@interface EVPKeyAgreement : NSObject

+ (instancetype)evpDH3KKeyAgreementWithModulus:(NSData*)modulus andGenerator:(NSData*)generator;
+ (instancetype)evpEC25KeyAgreement;

- (void)generateKeyPair;
- (NSData*)getPublicKey;
- (NSData*)getSharedSecretForRemotePublicKey:(NSData*)publicKey;

@end
