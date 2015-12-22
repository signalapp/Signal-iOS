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
        cp(CallProgressType_Connecting) : TXT_IN_CALL_CONNECTING,
        cp(CallProgressType_Ringing) : TXT_IN_CALL_RINGING,
        cp(CallProgressType_Securing) : TXT_IN_CALL_SECURING,
        cp(CallProgressType_Talking) : TXT_IN_CALL_TALKING,
        cp(CallProgressType_Terminated) : TXT_IN_CALL_TERMINATED
    };
}
NSDictionary *makeCallTerminationLocalizedTextDictionary(void) {
    return @{
        ct(CallTerminationType_NoSuchUser) : TXT_END_CALL_NO_SUCH_USER,
        ct(CallTerminationType_LoginFailed) : TXT_END_CALL_LOGIN_FAILED,
        ct(CallTerminationType_ResponderIsBusy) : TXT_END_CALL_RESPONDER_IS_BUSY,
        ct(CallTerminationType_StaleSession) : TXT_END_CALL_STALE_SESSION,
        ct(CallTerminationType_UncategorizedFailure) : TXT_END_CALL_UNCATEGORIZED_FAILURE,
        ct(CallTerminationType_ReplacedByNext) : TXT_END_CALL_REPLACED_BY_NEXT,
        ct(CallTerminationType_RecipientUnavailable) : TXT_END_CALL_RECIPIENT_UNAVAILABLE,
        ct(CallTerminationType_BadInteractionWithServer) : TXT_END_CALL_BAD_INTERACTION_WITH_SERVER,
        ct(CallTerminationType_HandshakeFailed) : TXT_END_CALL_HANDSHAKE_FAILED,
        ct(CallTerminationType_HangupRemote) : TXT_END_CALL_HANGUP_REMOTE,
        ct(CallTerminationType_HangupLocal) : TXT_END_CALL_HANGUP_LOCAL,
        ct(CallTerminationType_ServerMessage) : TXT_END_CALL_MESSAGE_FROM_SERVER_PREFIX,
        ct(CallTerminationType_RejectedLocal) : TXT_END_CALL_REJECTED_LOCAL,
        ct(CallTerminationType_RejectedRemote) : TXT_END_CALL_REJECTED_REMOTE
    };
}
