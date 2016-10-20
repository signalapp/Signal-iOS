#import "LocalizableText.h"

CallTermination *ct(enum CallTerminationType t);
CallTermination *ct(enum CallTerminationType t) {
    return [CallTermination callTerminationOfType:t withFailure:nil andMessageInfo:nil];
}
CallProgress *cp(enum CallProgressType t);
CallProgress *cp(enum CallProgressType t) {
    return [CallProgress callProgressWithType:t];
}

NSDictionary *makeCallProgressLocalizedTextDictionary(void) {
    return @{
        cp(CallProgressType_Connecting) : NSLocalizedString(@"IN_CALL_CONNECTING", @"Call setup status label"),
        cp(CallProgressType_Ringing) : NSLocalizedString(@"IN_CALL_RINGING", @"Call setup status label"),
        cp(CallProgressType_Securing) : NSLocalizedString(@"IN_CALL_SECURING", @"Call setup status label"),
        cp(CallProgressType_Talking) : NSLocalizedString(@"IN_CALL_TALKING", @"Call setup status label"),
        cp(CallProgressType_Terminated) : NSLocalizedString(@"IN_CALL_TERMINATED", @"Call setup status label")
    };
}
NSDictionary *makeCallTerminationLocalizedTextDictionary(void) {
    return @{
        ct(CallTerminationType_NoSuchUser) : NSLocalizedString(@"END_CALL_NO_SUCH_USER", @""),
        ct(CallTerminationType_LoginFailed) : NSLocalizedString(@"END_CALL_LOGIN_FAILED", @""),
        ct(CallTerminationType_ResponderIsBusy) : NSLocalizedString(@"END_CALL_RESPONDER_IS_BUSY", @""),
        ct(CallTerminationType_StaleSession) : NSLocalizedString(@"END_CALL_STALE_SESSION", @""),
        ct(CallTerminationType_UncategorizedFailure) : NSLocalizedString(@"END_CALL_UNCATEGORIZED_FAILURE", @""),
        ct(CallTerminationType_ReplacedByNext) : NSLocalizedString(@"END_CALL_REPLACED_BY_NEXT", @""),
        ct(CallTerminationType_RecipientUnavailable) : NSLocalizedString(@"END_CALL_RECIPIENT_UNAVAILABLE", @""),
        ct(CallTerminationType_BadInteractionWithServer) :
            NSLocalizedString(@"END_CALL_BAD_INTERACTION_WITH_SERVER", @""),
        ct(CallTerminationType_HandshakeFailed) : NSLocalizedString(@"END_CALL_HANDSHAKE_FAILED", @""),
        ct(CallTerminationType_HangupRemote) : NSLocalizedString(@"END_CALL_HANGUP_REMOTE", @""),
        ct(CallTerminationType_HangupLocal) : NSLocalizedString(@"END_CALL_HANGUP_LOCAL", @""),
        ct(CallTerminationType_ServerMessage) : NSLocalizedString(@"END_CALL_MESSAGE_FROM_SERVER_PREFIX", @""),
        ct(CallTerminationType_RejectedLocal) : NSLocalizedString(@"END_CALL_REJECTED_LOCAL", @""),
        ct(CallTerminationType_RejectedRemote) : NSLocalizedString(@"END_CALL_REJECTED_REMOTE", @"")
    };
}
