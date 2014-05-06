#import <Foundation/Foundation.h>
#import "KeyAgreementProtocol.h"
#import "KeyAgreementParticipant.h"

/// A mock key agreement protocol.
/// Used in testing to create key agreement participants with preset keys.
/// It would be very bad if one of these was used in non-testing code...

@interface PregeneratedKeyAgreementParticipantProtocol : NSObject <KeyAgreementProtocol> {
@private id<KeyAgreementParticipant> participant;
}

+(PregeneratedKeyAgreementParticipantProtocol*) pregeneratedWithParticipant:(id<KeyAgreementParticipant>)participant;
@end
