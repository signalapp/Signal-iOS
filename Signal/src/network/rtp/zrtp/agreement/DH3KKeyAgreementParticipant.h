#import <Foundation/Foundation.h>
#import "KeyAgreementParticipant.h"
#import "DH3KKeyAgreementProtocol.h"
#import "EVPKeyAgreement.h"

/**
 *
 * DH3KKeyAgreementParticipant is used to do Diffie-Hellman key agreement.
 * Each participant has access to the protocol parameters, and their own key material.
 *
**/

@interface DH3KKeyAgreementParticipant :  NSObject <KeyAgreementParticipant>

- (instancetype)initWithPrivateKeyGeneratedForProtocol:(DH3KKeyAgreementProtocol*)protocol;

@end
