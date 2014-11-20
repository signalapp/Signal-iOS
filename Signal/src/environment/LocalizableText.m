#import "LocalizableText.h"

CallTermination* ct(CallTerminationType t);
CallTermination* ct(CallTerminationType t) {
    return [[CallTermination alloc] initWithType:t andFailure:nil andMessageInfo:nil];
}
CallProgress* cp(CallProgressType t);
CallProgress* cp(CallProgressType t) {
    return [[CallProgress alloc] initWithType:t];
}

NSDictionary* makeCallProgressLocalizedTextDictionary(void) {
    return @{
             cp(CallProgressTypeConnecting): TXT_IN_CALL_CONNECTING,
             cp(CallProgressTypeRinging): TXT_IN_CALL_RINGING,
             cp(CallProgressTypeSecuring): TXT_IN_CALL_SECURING,
             cp(CallProgressTypeTalking): TXT_IN_CALL_TALKING,
             cp(CallProgressTypeTerminated): TXT_IN_CALL_TERMINATED
             };
    
}
NSDictionary* makeCallTerminationLocalizedTextDictionary(void) {
    return @{
             ct(CallTerminationTypeNoSuchUser): TXT_END_CALL_NO_SUCH_USER,
             ct(CallTerminationTypeLoginFailed): TXT_END_CALL_LOGIN_FAILED,
             ct(CallTerminationTypeResponderIsBusy): TXT_END_CALL_RESPONDER_IS_BUSY,
             ct(CallTerminationTypeStaleSession): TXT_END_CALL_STALE_SESSION,
             ct(CallTerminationTypeUncategorizedFailure): TXT_END_CALL_UNCATEGORIZED_FAILURE,
             ct(CallTerminationTypeReplacedByNext): TXT_END_CALL_REPLACED_BY_NEXT,
             ct(CallTerminationTypeRecipientUnavailable): TXT_END_CALL_RECIPIENT_UNAVAILABLE,
             ct(CallTerminationTypeBadInteractionWithServer): TXT_END_CALL_BAD_INTERACTION_WITH_SERVER,
             ct(CallTerminationTypeHandshakeFailed): TXT_END_CALL_HANDSHAKE_FAILED,
             ct(CallTerminationTypeHangupRemote): TXT_END_CALL_HANGUP_REMOTE,
             ct(CallTerminationTypeHangupLocal): TXT_END_CALL_HANGUP_LOCAL,
             ct(CallTerminationTypeServerMessage): TXT_END_CALL_MESSAGE_FROM_SERVER_PREFIX,
             ct(CallTerminationTypeRejectedLocal): TXT_END_CALL_REJECTED_LOCAL,
             ct(CallTerminationTypeRejectedRemote): TXT_END_CALL_REJECTED_REMOTE
             };
}
