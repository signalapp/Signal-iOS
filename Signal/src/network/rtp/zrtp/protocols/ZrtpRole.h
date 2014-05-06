#import <Foundation/Foundation.h>
#import "Environment.h"
#import "HandshakePacket.h"
#import "MasterSecret.h"
#import "SrtpSocket.h"

typedef enum {
    EXPECTING_HELLO,
    EXPECTING_COMMIT,
    EXPECTING_HELLO_ACK,
    EXPECTING_DH,
    EXPECTING_CONFIRM,
    EXPECTING_CONFIRM_ACK,
    EXPECTING_NOTHING
} PacketExpectation;

/**
 *
 * A ZrtpRole represents the responsibilities of a participant in a Zrtp handshake (either the initiator or the responder).
 * The role determines how packets are handled, which packets to send, and exposes the eventual results of the handshake.
 *
**/

@protocol ZrtpRole

// The packet to be sent when the handshake starts. Nil indicates 'Do not send an initial packet.'.
-(HandshakePacket*) initialPacket;

// Called when a packet arrives from the remote end of the handshake.
// Returns the packet to reply with. A nil result indicates 'Ignore Packet. Continue as before.'.
-(HandshakePacket*) handlePacket:(HandshakePacket*)packet;

// Determines if the handshake process has completed successfully.
-(bool) hasHandshakeFinishedSuccessfully;

// Determines if a 'bad' packet is actually valid authenticated srtp audio data, being received due to Conf2Ack being lost.
-(bool) isAuthenticatedAudioDataImplyingConf2Ack:(id)packet;

// Retrieves an srtp socket that has been keyed by the handshake process.
// Should only be called when 'hasHandshakeFinishedSuccessfully' is true.
-(SrtpSocket*) useKeysToSecureRtpSocket:(RtpSocket*)rtpSocket;

// Retrieves the computed master secret.
// Should only be called when 'hasHandshakeFinishedSuccessfully' is true.
-(MasterSecret*) getMasterSecret;
@end
