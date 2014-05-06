#import <Foundation/Foundation.h>

#import "CallController.h"
#import "CancelTokenSource.h"
#import "FutureSource.h"
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
    
@private CancelTokenSource* cancelTokenSource;
@private CancelTokenSource* currentRetransmit;
@private RtpSocket* rtpSocketToSecure;
@private ZrtpHandshakeSocket* handshakeSocket;
@private HandshakePacket* currentPacketToRetransmit;
@private id<ZrtpRole> zrtpRole;
@private FutureSource* futureHandshakeResultSource;
@private CallController* callController;
}

/// Starts a zrtp handshake over the given RtpSocket.
/// The given role type determines if we play the initiator role or the responder role,
/// All cryptographic keys and settings are either generated on the fly or pulled from the Environment.
///
/// @return
/// The asynchronous result has type Future(ZrtpHandshakeResult).
/// If the handshake completes succesfully, the resulting ZrtpHandshakeResult contains the SrtpSocket to be used for sending audio.
/// If the handshake timeout or otherwise fails to complete, the result will contain a failure.
/// If the handshake is cancelled, the result will contain a failure containing the cancellation token.
///
/// @param rtpSocket
/// The socket to perform the handshake over.
/// ZrtpManager will start the socket, handling and sending rtp packets over it.
///
/// @param callController
/// Used to notify the outside about the progress of termination of the handshake.
/// If callController's cancel token is cancelled before or while the handshake is running, the handshake will be promptly aborted.
+(Future*) asyncPerformHandshakeOver:(RtpSocket*)rtpSocket
                   andCallController:(CallController*)callController;

@end
