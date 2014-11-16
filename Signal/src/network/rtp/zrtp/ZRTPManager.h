#import <Foundation/Foundation.h>

#import "CallController.h"
#import "HandshakePacket.h"
#import "Logging.h"
#import "NegotiationFailed.h"
#import "RecipientUnavailable.h"
#import "ZRTPHandshakeResult.h"
#import "ZRTPHandshakeSocket.h"
#import "ZRTPRole.h"

/**
 *
 * ZRTPManager is the 'entry point' for the zrtp code.
 * ZRTPManager is a utility class for performing ZRTP handshakes, securing an RTPSocket into an SRTPSocket.
 *
 **/

@interface ZRTPManager : NSObject <Terminable>

/// Starts a zrtp handshake over the given RTPSocket.
/// The CallController's isInitiator state determines if we play the zrtp initiator or responder role,
/// All cryptographic keys and settings are either generated on the fly or pulled from the Environment.
///
/// @return
/// The asynchronous result has type Future(ZRTPHandshakeResult).
/// If the handshake completes succesfully, the resulting ZRTPHandshakeResult contains the SRTPSocket to be used for sending audio.
/// If the handshake times out, fails to complete, or is cancelled (via the call controller's untilCancelledToken),
/// the returned future will be given a failure.
///
/// @param rtpSocket
/// The socket to perform the handshake over.
/// ZRTPManager will start the socket, handling and sending rtp packets over it.
///
/// @param callController
/// Used to notify the outside about the progress of termination of the handshake.
/// If callController's cancel token is cancelled before or while the handshake is running, the handshake will be promptly aborted.
+ (TOCFuture*)asyncPerformHandshakeOver:(RTPSocket*)rtpSocket
                      andCallController:(CallController*)callController;

@end
