#import "EC25KeyAgreementProtocol.h"
#import "EC25KeyAgreementParticipant.h"
@implementation EC25KeyAgreementProtocol

+(EC25KeyAgreementProtocol*) protocol{
    return [EC25KeyAgreementProtocol new];
}

-(id<KeyAgreementParticipant>) generateParticipantWithNewKeys{
    return  [EC25KeyAgreementParticipant participantWithPrivateKeyGeneratedForProtocol:self];
}
-(NSData*) getId{
    return EC25_KEY_AGREEMENT_ID;
}
@end
