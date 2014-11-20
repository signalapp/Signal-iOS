#import <Foundation/Foundation.h>
#import "ZRTPRole.h"
#import "DHPacketSharedSecretHashes.h"
#import "CallController.h"

/**
 *
 * A ZRTPInitiator implements the 'initiator' role of the zrtp handshake.
 *
 * The initiator is NOT the one responsible for sending the first handshake packet.
 * The 'initiator' name is related to what happens during signaling, not the zrtp handshake.
 * The initiator receives Hello, sends Hello, receives HelloAck, sends Commit, receives DH1, sends DH2, receives Confirm1, sends Confirm2, and receives ConfirmAck
 *
**/

@interface ZRTPInitiator : NSObject <ZRTPRole>

- (instancetype)initWithCallController:(CallController*)callController;


@end
