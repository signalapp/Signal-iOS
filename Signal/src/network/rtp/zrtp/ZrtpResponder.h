#import <Foundation/Foundation.h>
#import "ZrtpRole.h"
#import "DhPacketSharedSecretHashes.h"
#import "CallController.h"

/**
 *
 * A ZrtpResponder implements the 'responder' role of the zrtp handshake.
 *
 * The responder SENDS the first handshake packet.
 * The 'responder' name is related to what happens during signaling, not the zrtp handshake.
 * The responder sends Hello, receives Hello, sends HelloAck, receives Commit, sends DH1, receives DH2, sends Confirm1, receives Confirm2, and sends ConfirmAck
 *
**/

@interface ZrtpResponder : NSObject <ZrtpRole> {
@private HelloPacket* localHello;
@private HelloPacket* foreignHello;
@private CommitPacket* foreignCommit;
@private DhPacket* localDH;
@private DhPacket* foreignDH;
@private NSArray* allowedKeyAgreementProtocols;
@private id<KeyAgreementParticipant> keyAgreementParticipant;
@private HashChain* hashChain;
@private MasterSecret* masterSecret;
@private NSData* confirmIv;
@private DhPacketSharedSecretHashes* dhSharedSecretHashes;
@private id<OccurrenceLogger> badPacketLogger;
@private PacketExpectation packetExpectation;
@private CallController* callController;
}

+(ZrtpResponder*) zrtpResponderWithCallController:(CallController*)callController;

@end
