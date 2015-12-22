#import <Foundation/Foundation.h>

enum CallTerminationType {
    // -- while connecting --
    CallTerminationType_LoginFailed,   /// The signaling server said our authentication details were wrong.
    CallTerminationType_NoSuchUser,    /// The signaling server said there's red phone user with that number.
    CallTerminationType_StaleSession,  /// The signaling server said the call we're trying to respond to managed to end
                                       /// before we made contact.
    CallTerminationType_ServerMessage, /// The signaling server said we should display a custom message (it's in the
                                       /// messageInfo property).

    // -- while ringing --
    CallTerminationType_ResponderIsBusy, /// The signaling server said the responder can't answer because they're busy.
    CallTerminationType_RecipientUnavailable, /// The signaling server said the responder never contacted it about the
                                              /// incoming call.
    CallTerminationType_RejectedLocal,        /// We did not accept the call.
    CallTerminationType_RejectedRemote,       /// The signaling server said the other side hung up (before handshake).

    // -- while securing --
    CallTerminationType_HandshakeFailed,        /// Something went wrong in the middle of the zrtp handshake.
    CallTerminationType_InvalidRemotePublicKey, /// The publickey supplied from the remote participant was not valid

    // -- anytime --
    CallTerminationType_HangupLocal,    /// We hung up.
    CallTerminationType_HangupRemote,   /// The signaling server said the other side hung up (after they accepted).
    CallTerminationType_ReplacedByNext, /// We automatically hung up because we started another call. (e.g. incoming
                                        /// call cancelled by us dialing out)

    // -- uh oh --
    CallTerminationType_BadInteractionWithServer, /// The signaling or relay server did something we didn't expect or
                                                  /// understand.
    CallTerminationType_UncategorizedFailure,  /// Something went wrong. We didn't handle it properly, so we don't know
                                               /// what exactly it was.
    CallTerminationType_BackgroundTimeExpired, /// The application expired available time while in background.
};

/**
 *
 * The CallTermination class is just an NSObject wrapper for the CallTerminationType enum.
 *
 **/

@interface CallTermination : NSObject <NSCopying>

@property (readonly, nonatomic) enum CallTerminationType type;
@property (readonly, nonatomic) id failure;
@property (readonly, nonatomic) id messageInfo;

+ (CallTermination *)callTerminationOfType:(enum CallTerminationType)type
                               withFailure:(id)failure
                            andMessageInfo:(id)messageInfo;
- (NSString *)localizedDescriptionForUser;

@end
