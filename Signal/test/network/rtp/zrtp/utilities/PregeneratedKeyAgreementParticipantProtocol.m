#import "PregeneratedKeyAgreementParticipantProtocol.h"

@implementation PregeneratedKeyAgreementParticipantProtocol

+(PregeneratedKeyAgreementParticipantProtocol*) pregeneratedWithParticipant:(id<KeyAgreementParticipant>)participant {
    PregeneratedKeyAgreementParticipantProtocol* s = [PregeneratedKeyAgreementParticipantProtocol new];
    s->participant = participant;
    return s;
}

-(id<KeyAgreementParticipant>) generateParticipantWithNewKeys {
    return participant;
}
-(NSData*) getId {
    return participant.getProtocol.getId;
}

@end
