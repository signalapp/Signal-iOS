#import <Foundation/Foundation.h>
#import "KeyAgreementParticipant.h"
#import "EC25KeyAgreementProtocol.h"
#import "EVPKeyAgreement.h"

@interface EC25KeyAgreementParticipant : NSObject <KeyAgreementParticipant>

- (instancetype)initWithPrivateKeyGeneratedForProtocol:(EC25KeyAgreementProtocol*)protocol;

@end
