#import <Foundation/Foundation.h>
#import "HashChain.h"
#import "HandshakePacket.h"

@protocol KeyAgreementProtocol;

/**
 *
 * KeyAgreementParticipant is used to represent a participant, with their own private/public key, in a key agreement protocol.
 * Two compatible participants generate shared key when given each others' public key data.
 *
**/

@protocol KeyAgreementParticipant
-(id<KeyAgreementProtocol>) getProtocol;
-(NSData*) getPublicKeyData;
-(NSData*) calculateKeyAgreementAgainstRemotePublicKey:(NSData*)remotePublicKey;
@end
