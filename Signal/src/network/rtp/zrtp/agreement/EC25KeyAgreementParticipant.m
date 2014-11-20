#import "EC25KeyAgreementParticipant.h"
#import "EVPKeyAgreement.h"
#import "Constraints.h"

@interface EC25KeyAgreementParticipant ()

@property (strong, nonatomic) EVPKeyAgreement* evpKeyAgreement;
@property (strong, nonatomic) EC25KeyAgreementProtocol* protocol;

@end

@implementation EC25KeyAgreementParticipant

- (instancetype)initWithPrivateKeyGeneratedForProtocol:(EC25KeyAgreementProtocol*)protocol {
    self = [super init];
	
    if (self) {
        self.protocol = protocol;
        self.evpKeyAgreement = [EVPKeyAgreement evpEC25KeyAgreement];
        [self.evpKeyAgreement generateKeyPair];
    }
    
    return self;
}

- (id<KeyAgreementProtocol>)getProtocol {
    return self.protocol;
}

- (NSData*)getPublicKeyData {
    return  self.evpKeyAgreement.getPublicKey;
}

- (NSData*)calculateKeyAgreementAgainstRemotePublicKey:(NSData*)remotePublicKey {
    return [self.evpKeyAgreement getSharedSecretForRemotePublicKey:remotePublicKey];
}
@end
