#import <Foundation/Foundation.h>
#import "HashChain.h"
#import "HandshakePacket.h"

@protocol KeyAgreementParticipant;

/**
 *
 * KeyAgreementProtocol is used to generate compatible participants for a key agreement protocol.
 * Two compatible participants generate shared key when given each others' public key data.
 *
**/

@protocol KeyAgreementProtocol
-(id<KeyAgreementParticipant>) generateParticipantWithNewKeys;
-(NSData*) getId;
@end
