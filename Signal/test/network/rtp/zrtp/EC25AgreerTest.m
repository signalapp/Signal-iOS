#import <XCTest/XCTest.h>
#import "TestUtil.h"

@interface EC25AgreerTest : XCTestCase
@end

@implementation EC25AgreerTest

-(void) testKeyExchangeMatchesPeerButNotOthers {
    EC25KeyAgreementProtocol* protocol = [EC25KeyAgreementProtocol protocol];
    
    id<KeyAgreementParticipant> ec1 = [protocol generateParticipantWithNewKeys];
    id<KeyAgreementParticipant> ec2 = [protocol generateParticipantWithNewKeys];
    id<KeyAgreementParticipant> ec3 = [protocol generateParticipantWithNewKeys];
    
    NSData* pub_1 = ec1.getPublicKeyData;
    NSData* pub_2 = ec2.getPublicKeyData;
    
    NSData* shared_1 = [ec1 calculateKeyAgreementAgainstRemotePublicKey:pub_2];
    NSData* shared_2 = [ec2 calculateKeyAgreementAgainstRemotePublicKey:pub_1];
    
    test([shared_1 isEqualToData:shared_2]);
    
    NSData* shared_3 = [ec3 calculateKeyAgreementAgainstRemotePublicKey:pub_1];
    
    test(![shared_3 isEqualToData:shared_1]);
}

-(void) testKeyExchangeSucceedsConsistently {
    EC25KeyAgreementProtocol* protocol = [EC25KeyAgreementProtocol protocol];
    for (int i = 0; i < 1000; i++) {
        id<KeyAgreementParticipant> ec1 = [protocol generateParticipantWithNewKeys];
        id<KeyAgreementParticipant> ec2 = [protocol generateParticipantWithNewKeys];

        NSData* pub_1 = ec1.getPublicKeyData;
        NSData* pub_2 = ec2.getPublicKeyData;
    
        NSData* shared_1 = [ec1 calculateKeyAgreementAgainstRemotePublicKey:pub_2];
        NSData* shared_2 = [ec2 calculateKeyAgreementAgainstRemotePublicKey:pub_1];
    
        test([shared_1 isEqualToData:shared_2]);
    }
}

@end
