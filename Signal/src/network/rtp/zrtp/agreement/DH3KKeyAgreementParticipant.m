#import "DH3KKeyAgreementParticipant.h"

@implementation DH3KKeyAgreementParticipant

+(DH3KKeyAgreementParticipant*) participantWithPrivateKeyGeneratedForProtocol:(DH3KKeyAgreementProtocol*) protocol {
    assert(nil != protocol);
    
    DH3KKeyAgreementParticipant* participant = [DH3KKeyAgreementParticipant new];
    
    participant->protocol = protocol;
    participant->evpKeyAgreement = [EvpKeyAgreement evpDh3kKeyAgreementWithModulus:protocol.getModulus andGenerator:protocol.getGenerator];
    return participant;
}

-(id<KeyAgreementProtocol>) getProtocol{
    return self->protocol;
}

-(NSData*) getPublicKeyData{
    return self->evpKeyAgreement.getPublicKey;
}

-(NSData*) calculateKeyAgreementAgainstRemotePublicKey:(NSData*)remotePublicKey{
    return [self->evpKeyAgreement getSharedSecretForRemotePublicKey:remotePublicKey];
}

@end
