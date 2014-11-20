#import "EC25KeyAgreementProtocol.h"
#import "EC25KeyAgreementParticipant.h"

#define EC25_KEY_AGREEMENT_ID @"EC25".encodedAsUtf8

@implementation EC25KeyAgreementProtocol

- (id<KeyAgreementParticipant>)generateParticipantWithNewKeys {
    return  [[EC25KeyAgreementParticipant alloc] initWithPrivateKeyGeneratedForProtocol:self];
}

- (NSData*)getId {
    return EC25_KEY_AGREEMENT_ID;
}

@end
