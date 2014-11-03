#import <Foundation/Foundation.h>

#import "CallController.h"
#import "HandshakePacket.h"
#import "Logging.h"
#import "NegotiationFailed.h"
#import "RecipientUnavailable.h"
#import "ZrtpHandshakeResult.h"
#import "ZrtpHandshakeSocket.h"
#import "ZrtpRole.h"

/**
 *
 * ZrtpManager is the 'entry point' for the zrtp code.
 * ZrtpManager is a utility class for performing ZRTP handshakes, securing an RtpSocket into an SrtpSocket.
 *
 **/

@interface ZrtpManager : NSObject<Terminable> {
@private int32_t currentPacketTransmitCount;
@private bool handshakeCompletedSuccesfully;
@private bool done;
    
@private TOCCancelTokenSource* cancelTokenSource;
@private TOCCancelTokenSource* currentRetransmit;
@private RtpSocket* rtpSocketToSecure;
@private ZrtpHandshakeSocket* handshakeSocket;
@private HandshakePacket* currentPacketToRetransmit;
@private id<ZrtpRole> zrtpRole;
@private TOCFutureSource* futureHandshakeResultSource;
@private CallController* callController;
}

/// Starts a zrtp handshake over the given RtpSocket.
/// The CallController's isInitiator state determines if we play the zrtp initiator or responder role,
/// All cryptographic keys and settings are either generated on the fly or pulled from the Environment.
///
/// @return
/// The asynchronous result has type Future(ZrtpHandshakeResult).
/// If the handshake completes succesfully, the resulting ZrtpHandshakeResult contains the SrtpSocket to be used for sending audio.
/// If the handshake times out, fails to complete, or is cancelled (via the call controller's untilCancelledToken),
/// the returned future will be given a failure.
///
/// @param rtpSocket
/// The socket to perform the handshake over.
/// ZrtpManager will start the socket, handling and sending rtp packets over it.
///
/// @param callController
/// Used to notify the outside about the progress of termination of the handshake.
/// If callController's cancel token is cancelled before or while the handshake is running, the handshake will be promptly aborted.
+(TOCFuture*) asyncPerformHandshakeOver:(RtpSocket*)rtpSocket
                      andCallController:(CallController*)callController;

@end
