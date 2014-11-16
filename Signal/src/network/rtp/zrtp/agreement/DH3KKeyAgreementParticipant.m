#import "DH3KKeyAgreementParticipant.h"

@interface DH3KKeyAgreementParticipant ()

@property (strong, nonatomic) DH3KKeyAgreementProtocol* protocol;
@property (strong, nonatomic) EVPKeyAgreement* evpKeyAgreement;

@end

@implementation DH3KKeyAgreementParticipant

- (instancetype)initWithPrivateKeyGeneratedForProtocol:(DH3KKeyAgreementProtocol*)protocol {
    if (self = [super init]) {
        assert(nil != protocol);
        
        self.protocol = protocol;
        self.evpKeyAgreement = [EVPKeyAgreement evpDH3KKeyAgreementWithModulus:protocol.getModulus andGenerator:protocol.getGenerator];
    }
    
    return self;
}

- (id<KeyAgreementProtocol>)getProtocol {
    return self.protocol;
}

- (NSData*)getPublicKeyData {
    return self.evpKeyAgreement.getPublicKey;
}

- (NSData*)calculateKeyAgreementAgainstRemotePublicKey:(NSData*)remotePublicKey {
    return [self.evpKeyAgreement getSharedSecretForRemotePublicKey:remotePublicKey];
}

@end
