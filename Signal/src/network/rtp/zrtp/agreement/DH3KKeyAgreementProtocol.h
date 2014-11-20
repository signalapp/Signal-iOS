#import <Foundation/Foundation.h>
#import "KeyAgreementProtocol.h"
#import "CryptoTools.h"

/**
 *
 * DH3KKeyAgreementProtocol is used to generate participants for Diffie-Hellman key agreement.
 *
**/

@interface DH3KKeyAgreementProtocol : NSObject <KeyAgreementProtocol>

@property (strong, readonly, nonatomic, getter=getModulus) NSData* modulus;
@property (strong, readonly, nonatomic, getter=getGenerator) NSData* generator;

- (instancetype)initWithModulus:(NSData*)modulus andGenerator:(NSData*)generator;

@end
