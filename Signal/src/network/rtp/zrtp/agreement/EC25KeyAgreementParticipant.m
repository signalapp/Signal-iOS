#import "EC25KeyAgreementParticipant.h"

@implementation EC25KeyAgreementParticipant

+(EC25KeyAgreementParticipant*) participantWithPrivateKeyGeneratedForProtocol:(EC25KeyAgreementProtocol*)protocol{
    return  [[EC25KeyAgreementParticipant alloc] initWithProtocol:protocol];
}

-(EC25KeyAgreementParticipant*) initWithProtocol:(EC25KeyAgreementProtocol*) proto {
    protocol = proto;
    evpKeyAgreement = [EvpKeyAgreement evpEc25KeyAgreement];
    [evpKeyAgreement generateKeyPair];
    return  self;
}

-(id<KeyAgreementProtocol>) getProtocol{
    return protocol;
}

-(NSData*) getPublicKeyData{
    return  evpKeyAgreement.getPublicKey;
}

-(NSData*) calculateKeyAgreementAgainstRemotePublicKey:(NSData*)remotePublicKey{
    return [evpKeyAgreement getSharedSecretForRemotePublicKey:remotePublicKey];
}
@end
