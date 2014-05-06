
#import <Foundation/Foundation.h>
#import "KeyAgreementParticipant.h"
#import "EC25KeyAgreementProtocol.h"
#import "EvpKeyAgreement.h"

@interface EC25KeyAgreementParticipant : NSObject<KeyAgreementParticipant>{
@private EvpKeyAgreement* evpKeyAgreement;
@private EC25KeyAgreementProtocol* protocol;
}

+(EC25KeyAgreementParticipant*) participantWithPrivateKeyGeneratedForProtocol:(EC25KeyAgreementProtocol*)protocol;

@end
