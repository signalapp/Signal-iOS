#import "SignalUtil.h"

#import "Constraints.h"
#import "Environment.h"
#import "PreferencesUtil.h"
#import "Util.h"
#import "SGNKeychainUtil.h"

#define CLAIMED_INTEROP_VERSION_IN_INITIATE_SIGNAL 1

/**
 *
 * Augments HttpRequest with utility methods related to interacting with signaling servers.
 *
 */
@implementation HttpRequest(SignalUtil)

-(NSNumber*) tryGetSessionId {
    if (![self.location hasPrefix:@"/session/"]) return nil;
    
    NSString* sessionIdText = [self.location substringFromIndex:@"/session/".length];
    sessionIdText = [sessionIdText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSNumber* sessionIdNumber = [sessionIdText tryParseAsDecimalNumber];

    if (sessionIdNumber.hasLongLongValue) return sessionIdNumber;
    
    return nil;
}

-(bool) isKeepAlive {
    return [self.method isEqualToString:@"GET"] && [self.location hasPrefix:@"/keepalive"];
}

-(bool) isRingingForSession:(int64_t)targetSessionId {
    return [self.method isEqualToString:@"RING"] && [@(targetSessionId) isEqualToNumber:[self tryGetSessionId]];
}

-(bool) isHangupForSession:(int64_t)targetSessionId {
    return [self.method isEqualToString:@"DELETE"] && [@(targetSessionId) isEqualToNumber:[self tryGetSessionId]];
}

-(bool) isBusyForSession:(int64_t)targetSessionId {
    return [self.method isEqualToString:@"BUSY"] && [@(targetSessionId) isEqualToNumber:[self tryGetSessionId]];
}

+(HttpRequest*) httpRequestToOpenPortWithSessionId:(int64_t)sessionId {
    return [HttpRequest httpRequestUnauthenticatedWithMethod:@"GET"
                                                 andLocation:[NSString stringWithFormat:@"/open/%lld", sessionId]];
}
+(HttpRequest*) httpRequestToRingWithSessionId:(int64_t)sessionId {
    return [HttpRequest httpRequestWithOtpAuthenticationAndMethod:@"RING"
                                                      andLocation:[NSString stringWithFormat:@"/session/%lld", sessionId]];
}
+(HttpRequest*) httpRequestToSignalBusyWithSessionId:(int64_t)sessionId {
    return [HttpRequest httpRequestWithOtpAuthenticationAndMethod:@"BUSY"
                                                      andLocation:[NSString stringWithFormat:@"/session/%lld", sessionId]];
}
+(HttpRequest*) httpRequestToInitiateToRemoteNumber:(PhoneNumber*)remoteNumber {
    require(remoteNumber != nil);
    
    NSString* formattedRemoteNumber = [remoteNumber toE164];
    NSString* interopVersionInsert = CLAIMED_INTEROP_VERSION_IN_INITIATE_SIGNAL == 0
                                   ? @""
                                   : [NSString stringWithFormat:@"/%d", CLAIMED_INTEROP_VERSION_IN_INITIATE_SIGNAL];
    return [HttpRequest httpRequestWithOtpAuthenticationAndMethod:@"GET"
                                                      andLocation:[NSString stringWithFormat:@"/session%@/%@",
                                                                   interopVersionInsert,
                                                                   formattedRemoteNumber]];
}
+(HttpRequest*) httpRequestToStartRegistrationOfPhoneNumber {
    return [HttpRequest httpRequestWithBasicAuthenticationAndMethod:@"GET"
                                                        andLocation:@"/users/verification"];
}

+(HttpRequest*) httpRequestToStartRegistrationOfPhoneNumberWithVoice {
    return [HttpRequest httpRequestWithBasicAuthenticationAndMethod:@"GET"
                                                        andLocation:@"/users/verification/voice"];
}

+(HttpRequest*) httpRequestToVerifyAccessToPhoneNumberWithChallenge:(NSString*)challenge {
    require(challenge != nil);
    
    PhoneNumber* localPhoneNumber = [SGNKeychainUtil localNumber];
    NSString* query = [NSString stringWithFormat:@"/users/verification/%@", [localPhoneNumber toE164]];
    [SGNKeychainUtil generateSignaling];
    
    NSData* signalingCipherKey = [SGNKeychainUtil signalingCipherKey];
    NSData* signalingMacKey = [SGNKeychainUtil signalingMacKey];
    NSData* signalingExtraKeyData = [SGNKeychainUtil signalingCipherKey];
    NSString* encodedSignalingKey = [[@[signalingCipherKey, signalingMacKey, signalingExtraKeyData] concatDatas] encodedAsBase64];
    NSString* body = [@{@"key" : encodedSignalingKey, @"challenge" : challenge} encodedAsJson];
    
    return [HttpRequest httpRequestWithBasicAuthenticationAndMethod:@"PUT"
                                                        andLocation:query
                                                    andOptionalBody:body];
}
+(HttpRequest*) httpRequestToRegisterForApnSignalingWithDeviceToken:(NSData*)deviceToken {
    require(deviceToken != nil);
    
    NSString* query = [NSString stringWithFormat:@"/apn/%@", [deviceToken encodedAsHexString]];
    
    return [HttpRequest httpRequestWithBasicAuthenticationAndMethod:@"PUT"
                                                        andLocation:query];
}

+(HttpRequest*) httpRequestForPhoneNumberDirectoryFilter {
    return [HttpRequest httpRequestWithOtpAuthenticationAndMethod:@"GET"
                                                      andLocation:@"/users/directory"];
}

@end
