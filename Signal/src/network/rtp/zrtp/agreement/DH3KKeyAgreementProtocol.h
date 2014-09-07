#import <Foundation/Foundation.h>
#import "KeyAgreementProtocol.h"
#import "CryptoTools.h"

#define DH3k_KEY_AGREEMENT_ID @"DH3k".encodedAsUtf8

/**
 *
 * DH3KKeyAgreementProtocol is used to generate participants for Diffie-Hellman key agreement.
 *
**/

@interface DH3KKeyAgreementProtocol : NSObject <KeyAgreementProtocol> {
@private NSData* modulus;
@private NSData* generator;
}

+(DH3KKeyAgreementProtocol*) protocolWithModulus:(NSData*)modulus andGenerator:(NSData*)generator;
-(NSData*) getGenerator;
-(NSData*) getModulus;

@end
