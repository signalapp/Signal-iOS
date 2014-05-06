#import <Foundation/Foundation.h>

#import "KeyAgreementParticipant.h"
#import "DH3KKeyAgreementProtocol.h"
#import "EvpKeyAgreement.h"

/**
 *
 * DH3KKeyAgreementParticipant is used to do Diffie-Hellman key agreement.
 * Each participant has access to the protocol parameters, and their own key material.
 *
**/

@interface DH3KKeyAgreementParticipant :  NSObject <KeyAgreementParticipant> {

@private DH3KKeyAgreementProtocol* protocol;
@private EvpKeyAgreement* evpKeyAgreement;

}

+(DH3KKeyAgreementParticipant*) participantWithPrivateKeyGeneratedForProtocol:(DH3KKeyAgreementProtocol*) protocol;

@end
