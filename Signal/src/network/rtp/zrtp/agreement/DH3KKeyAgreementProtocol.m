#import "DH3KKeyAgreementProtocol.h"
#import "DH3KKeyAgreementParticipant.h"
#import "Constraints.h"
#import "CryptoTools.h"
#import "Util.h"
#import "NSData+Conversions.h"
#import "EVPKeyAgreement.h"

#define DH3k_KEY_AGREEMENT_ID @"DH3k".encodedAsUtf8

@interface DH3KKeyAgreementProtocol ()

@property (strong, readwrite, nonatomic, getter=getModulus) NSData* modulus;
@property (strong, readwrite, nonatomic, getter=getGenerator) NSData* generator;

@end

@implementation DH3KKeyAgreementProtocol

- (instancetype)initWithModulus:(NSData*)modulus andGenerator:(NSData*)generator {
    if (self = [super init]) {
        assert(nil != modulus);
        assert(nil != generator);
        
        self.generator = generator;
        self.modulus = modulus;
    }
    
    return self;
}

- (id<KeyAgreementParticipant>)generateParticipantWithNewKeys {
    return [[DH3KKeyAgreementParticipant alloc] initWithPrivateKeyGeneratedForProtocol:self];
}

- (NSData*)getId {
    return DH3k_KEY_AGREEMENT_ID;
}

@end
