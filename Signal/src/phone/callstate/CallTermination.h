#import <Foundation/Foundation.h>

typedef enum {
    // -- while connecting --
    CallTerminationTypeLoginFailed, /// The signaling server said our authentication details were wrong.
    CallTerminationTypeNoSuchUser, /// The signaling server said there's red phone user with that number.
    CallTerminationTypeStaleSession, /// The signaling server said the call we're trying to respond to managed to end before we made contact.
    CallTerminationTypeServerMessage, /// The signaling server said we should display a custom message (it's in the messageInfo property).
    
    // -- while ringing --
    CallTerminationTypeResponderIsBusy, /// The signaling server said the responder can't answer because they're busy.
    CallTerminationTypeRecipientUnavailable, /// The signaling server said the responder never contacted it about the incoming call.
    CallTerminationTypeRejectedLocal, /// We did not accept the call.
    CallTerminationTypeRejectedRemote, /// The signaling server said the other side hung up (before handshake).

    // -- while securing --
    CallTerminationTypeHandshakeFailed, /// Something went wrong in the middle of the zrtp handshake.
    CallTerminationTypeInvalidRemotePublicKey, /// The publickey supplied from the remote participant was not valid
    
    // -- anytime --
    CallTerminationTypeHangupLocal, /// We hung up.
    CallTerminationTypeHangupRemote, /// The signaling server said the other side hung up (after they accepted).
    CallTerminationTypeReplacedByNext, /// We automatically hung up because we started another call. (e.g. incoming call cancelled by us dialing out)
    
    // -- uh oh --
    CallTerminationTypeBadInteractionWithServer, /// The signaling or relay server did something we didn't expect or understand.
    CallTerminationTypeUncategorizedFailure, /// Something went wrong. We didn't handle it properly, so we don't know what exactly it was.
} CallTerminationType;

/**
 *
 * The CallTermination class is just an NSObject wrapper for the CallTerminationType enum.
 *
 **/

@interface CallTermination : NSObject <NSCopying>

@property (readonly, nonatomic) CallTerminationType type;
@property (readonly, nonatomic) id failure;
@property (readonly, nonatomic) id messageInfo;

- (instancetype)initWithType:(CallTerminationType)type
                  andFailure:(id)failure
              andMessageInfo:(id)messageInfo;

- (NSString*)localizedDescriptionForUser;

@end
