#import <Foundation/Foundation.h>
#import "KeyAgreementProtocol.h"

#define EC25_KEY_AGREEMENT_ID @"EC25".encodedAsUtf8

@interface EC25KeyAgreementProtocol : NSObject<KeyAgreementProtocol>{
}

+(EC25KeyAgreementProtocol*) protocol;
-(id<KeyAgreementParticipant>) generateParticipantWithNewKeys;
-(NSData*) getId;

@end
