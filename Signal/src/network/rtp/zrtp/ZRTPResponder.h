#import <Foundation/Foundation.h>
#import "ZRTPRole.h"
#import "DHPacketSharedSecretHashes.h"
#import "CallController.h"

/**
 *
 * A ZRTPResponder implements the 'responder' role of the zrtp handshake.
 *
 * The responder SENDS the first handshake packet.
 * The 'responder' name is related to what happens during signaling, not the zrtp handshake.
 * The responder sends Hello, receives Hello, sends HelloAck, receives Commit, sends DH1, receives DH2, sends Confirm1, receives Confirm2, and sends ConfirmAck
 *
**/

@interface ZRTPResponder : NSObject <ZRTPRole>

- (instancetype)initWithCallController:(CallController*)callController;

@end
