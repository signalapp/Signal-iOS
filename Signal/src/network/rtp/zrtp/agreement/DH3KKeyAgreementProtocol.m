#import "DH3KKeyAgreementProtocol.h"
#import "DH3KKeyAgreementParticipant.h"

@implementation DH3KKeyAgreementProtocol

+(DH3KKeyAgreementProtocol*) protocolWithModulus:(NSData*)modulus andGenerator:(NSData*)generator {
    assert(nil != modulus);
    assert(nil != generator);
    
    DH3KKeyAgreementProtocol* keyAgreementProtocol = [DH3KKeyAgreementProtocol new];
    keyAgreementProtocol->generator = generator;
    keyAgreementProtocol->modulus = modulus;
    return keyAgreementProtocol;
}
-(NSData*) getGenerator {
    return generator;
}
-(NSData*) getModulus {
    return modulus;
}
-(id<KeyAgreementParticipant>) generateParticipantWithNewKeys {
    return [DH3KKeyAgreementParticipant participantWithPrivateKeyGeneratedForProtocol:self];
}
-(NSData*) getId {
    return DH3k_KEY_AGREEMENT_ID;
}
@end
