#import <Foundation/Foundation.h>

enum CallProgressType {
    /// Connecting covers:
    /// - The initiator is establishing connection (over tls/tcp) to the default signaling server
    /// - The initiator is requesting (using an http request) a call session to the to-be responder
    /// - The initiator is contacting (over udp) the relay server described in the call descriptor it received
    /// - The initiator has confirmed the session with the signaling server, but not yet received the 'Ringing' signal
    /// - The responder is notified (via a device notification) of an incoming call
    /// - The responder is contacting (over udp) the relay server described in the call descriptor it received
    CallProgressType_Connecting,

    /// Ringing covers:
    /// - The initiator has received a 'Ringing' signal from the signaling server it contacted
    /// - The initiator has not yet received a zrtp 'Hello' from the responder via the relay
    /// - The responder has confirmed the session with the signaling server
    /// - The responder's user has not yet accepted the incoming call
    CallProgressType_Ringing,

    /// Securing covers:
    /// - The initiator has received a zrtp 'Hello' from the responder
    /// - The initiator has not yet determined the handshake is over (by receiving a zrtp 'ConfAck' or authenticated
    /// audio data)
    /// - The responder's user has accepted the call (causing the responder to send zrtp 'Hello')
    /// - The responder has not yet determined the handshake is over (by receiving a zrtp 'Confirm2')
    CallProgressType_Securing,

    /// Talking covers:
    /// - Sending/Receiving encrypted and authenticated audio
    CallProgressType_Talking,

    /// Terminated covers:
    /// - Any of the call setup failed for whatever reason
    /// - Either of the users decided to hang up
    CallProgressType_Terminated
};

/**
 *
 * The CallProgress class is just an NSObject wrapper for the CallProgressType enum.
 *
 **/
@interface CallProgress : NSObject <NSCopying>

@property (nonatomic, readonly) enum CallProgressType type;

+ (CallProgress *)callProgressWithType:(enum CallProgressType)type;
- (NSString *)localizedDescriptionForUser;

@end
