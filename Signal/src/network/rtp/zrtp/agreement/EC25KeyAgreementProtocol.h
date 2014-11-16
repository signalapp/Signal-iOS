#import <Foundation/Foundation.h>
#import "KeyAgreementProtocol.h"

@interface EC25KeyAgreementProtocol : NSObject <KeyAgreementProtocol>

- (id<KeyAgreementParticipant>)generateParticipantWithNewKeys;
- (NSData*)getId;

@end
