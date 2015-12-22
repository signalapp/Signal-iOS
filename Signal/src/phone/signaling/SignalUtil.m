#import "SignalUtil.h"

#import <TextSecureKit/TSAccountManager.h>
#import "Constraints.h"
#import "SignalKeyingStorage.h"
#import "Util.h"

#define CLAIMED_INTEROP_VERSION_IN_INITIATE_SIGNAL 1

/**
 *
 * Augments HttpRequest with utility methods related to interacting with signaling servers.
 *
 */
@implementation HttpRequest (SignalUtil)

- (NSNumber *)tryGetSessionId {
    if (![self.location hasPrefix:@"/session/"])
        return nil;

    NSString *sessionIdText   = [self.location substringFromIndex:@"/session/".length];
    sessionIdText             = [sessionIdText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSNumber *sessionIdNumber = [sessionIdText tryParseAsDecimalNumber];

    if (sessionIdNumber.hasLongLongValue)
        return sessionIdNumber;

    return nil;
}

- (bool)isKeepAlive {
    return [self.method isEqualToString:@"GET"] && [self.location hasPrefix:@"/keepalive"];
}

- (bool)isRingingForSession:(int64_t)targetSessionId {
    NSNumber *sessionId = self.tryGetSessionId;
    BOOL isMethod       = [self.method isEqualToString:@"RING"];
    BOOL isSession      = sessionId ? [@(targetSessionId) isEqualToNumber:sessionId] : NO;

    return isMethod && isSession;
}

- (bool)isHangupForSession:(int64_t)targetSessionId {
    NSNumber *sessionId = self.tryGetSessionId;
    BOOL isMethod       = [self.method isEqualToString:@"DELETE"];
    BOOL isSession      = sessionId ? [@(targetSessionId) isEqualToNumber:sessionId] : NO;

    return isMethod && isSession;
}

- (bool)isBusyForSession:(int64_t)targetSessionId {
    NSNumber *sessionId = self.tryGetSessionId;
    BOOL isMethod       = [self.method isEqualToString:@"BUSY"];
    BOOL isSession      = sessionId ? [@(targetSessionId) isEqualToNumber:sessionId] : NO;

    return isMethod && isSession;
}

+ (HttpRequest *)httpRequestToOpenPortWithSessionId:(int64_t)sessionId {
    return [HttpRequest httpRequestUnauthenticatedWithMethod:@"GET"
                                                 andLocation:[NSString stringWithFormat:@"/open/%lld", sessionId]];
}
+ (HttpRequest *)httpRequestToRingWithSessionId:(int64_t)sessionId {
    return
        [HttpRequest httpRequestWithOtpAuthenticationAndMethod:@"RING"
                                                   andLocation:[NSString stringWithFormat:@"/session/%lld", sessionId]];
}
+ (HttpRequest *)httpRequestToSignalBusyWithSessionId:(int64_t)sessionId {
    return
        [HttpRequest httpRequestWithOtpAuthenticationAndMethod:@"BUSY"
                                                   andLocation:[NSString stringWithFormat:@"/session/%lld", sessionId]];
}
+ (HttpRequest *)httpRequestToInitiateToRemoteNumber:(PhoneNumber *)remoteNumber {
    ows_require(remoteNumber != nil);

    NSString *formattedRemoteNumber = remoteNumber.toE164;
    NSString *interopVersionInsert =
        CLAIMED_INTEROP_VERSION_IN_INITIATE_SIGNAL == 0
            ? @""
            : [NSString stringWithFormat:@"/%d", CLAIMED_INTEROP_VERSION_IN_INITIATE_SIGNAL];
    return [HttpRequest httpRequestWithOtpAuthenticationAndMethod:@"GET"
                                                      andLocation:[NSString stringWithFormat:@"/session%@/%@",
                                                                                             interopVersionInsert,
                                                                                             formattedRemoteNumber]];
}
+ (HttpRequest *)httpRequestToStartRegistrationOfPhoneNumber {
    return [HttpRequest httpRequestWithBasicAuthenticationAndMethod:@"GET" andLocation:@"/users/verification"];
}

+ (HttpRequest *)httpRequestToStartRegistrationOfPhoneNumberWithVoice {
    return [HttpRequest httpRequestWithBasicAuthenticationAndMethod:@"GET" andLocation:@"/users/verification/voice"];
}

+ (HttpRequest *)httpRequestToVerifyAccessToPhoneNumberWithChallenge:(NSString *)challenge {
    ows_require(challenge != nil);

    NSString *localPhoneNumber = [TSAccountManager localNumber];
    NSString *query            = [NSString stringWithFormat:@"/users/verification/%@", localPhoneNumber];
    [SignalKeyingStorage generateSignaling];

    NSData *signalingCipherKey    = SignalKeyingStorage.signalingCipherKey;
    NSData *signalingMacKey       = SignalKeyingStorage.signalingMacKey;
    NSData *signalingExtraKeyData = SignalKeyingStorage.signalingExtraKey;

    NSString *encodedSignalingKey =
        @[ signalingCipherKey, signalingMacKey, signalingExtraKeyData ].ows_concatDatas.encodedAsBase64;
    NSString *body = @{ @"key" : encodedSignalingKey, @"challenge" : challenge }.encodedAsJson;

    return [HttpRequest httpRequestWithBasicAuthenticationAndMethod:@"PUT" andLocation:query andOptionalBody:body];
}
+ (HttpRequest *)httpRequestToRegisterForApnSignalingWithDeviceToken:(NSData *)deviceToken {
    ows_require(deviceToken != nil);

    NSString *query = [NSString stringWithFormat:@"/apn/%@", deviceToken.encodedAsHexString];

    return [HttpRequest httpRequestWithBasicAuthenticationAndMethod:@"PUT" andLocation:query];
}

+ (HttpRequest *)httpRequestForPhoneNumberDirectoryFilter {
    return [HttpRequest httpRequestWithOtpAuthenticationAndMethod:@"GET" andLocation:@"/users/directory"];
}

@end
