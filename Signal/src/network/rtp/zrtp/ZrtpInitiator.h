#import <Foundation/Foundation.h>
#import "ZrtpRole.h"
#import "DhPacketSharedSecretHashes.h"
#import "CallController.h"

/**
 *
 * A ZrtpInitiator implements the 'initiator' role of the zrtp handshake.
 *
 * The initiator is NOT the one responsible for sending the first handshake packet.
 * The 'initiator' name is related to what happens during signaling, not the zrtp handshake.
 * The initiator receives Hello, sends Hello, receives HelloAck, sends Commit, receives DH1, sends DH2, receives Confirm1, sends Confirm2, and receives ConfirmAck
 *
**/

@interface ZrtpInitiator : NSObject <ZrtpRole> {
    
@private CommitPacket* commitPacket;
@private DhPacketSharedSecretHashes* dhSharedSecretHashes;
@private DhPacket* foreignDH;
@private DhPacket* localDH;
@private HashChain* hashChain;
@private HelloPacket* foreignHello;
@private HelloPacket* localHello;
@private id<KeyAgreementParticipant> keyAgreementParticipant;
@private id<OccurrenceLogger> badPacketLogger;
@private NSArray* allowedKeyAgreementProtocols;
@private NSData* confirmIv;
@private MasterSecret* masterSecret;
@private PacketExpectation packetExpectation;
@private Zid* zid;
@private CallController* callController;
}

+(ZrtpInitiator*) zrtpInitiatorWithCallController:(CallController*)callController;


@end
