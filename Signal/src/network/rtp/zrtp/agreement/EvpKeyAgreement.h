#import <Foundation/Foundation.h>
#import "DH3KKeyAgreementProtocol.h"
#import "KeyAgreementParticipant.h"

@interface EvpKeyAgreement : NSObject {
}

+(EvpKeyAgreement*) evpDh3kKeyAgreementWithModulus:(NSData*) modulus andGenerator:(NSData*) generator;
+(EvpKeyAgreement*) evpEc25KeyAgreement;


-(void) generateKeyPair;
-(NSData*) getPublicKey;
-(NSData*) getSharedSecretForRemotePublicKey:(NSData*) publicKey;

@end
