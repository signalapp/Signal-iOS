#import "HTTPRequest+SignalUtil.h"
#import "Constraints.h"
#import "Environment.h"
#import "PropertyListPreferences+Util.h"
#import "Util.h"
#import "SGNKeychainUtil.h"

#define CLAIMED_INTEROP_VERSION_IN_INITIATE_SIGNAL 1

/**
 *
 * Augments HTTPRequest with utility methods related to interacting with signaling servers.
 *
 */
@implementation HTTPRequest (SignalUtil)

- (NSNumber*)tryGetSessionId {
    if (![self.location hasPrefix:@"/session/"]) return nil;
    
    NSString* sessionIdText = [self.location substringFromIndex:@"/session/".length];
    sessionIdText = [sessionIdText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSNumber* sessionIdNumber = [sessionIdText tryParseAsDecimalNumber];

    if (sessionIdNumber.hasLongLongValue) return sessionIdNumber;
    
    return nil;
}

- (bool)isKeepAlive {
    return [self.method isEqualToString:@"GET"] && [self.location hasPrefix:@"/keepalive"];
}

- (bool)isRingingForSession:(int64_t)targetSessionId {
    return [self.method isEqualToString:@"RING"] && [@(targetSessionId) isEqualToNumber:self.tryGetSessionId];
}

- (bool)isHangupForSession:(int64_t)targetSessionId {
    return [self.method isEqualToString:@"DELETE"] && [@(targetSessionId) isEqualToNumber:self.tryGetSessionId];
}

- (bool)isBusyForSession:(int64_t)targetSessionId {
    return [self.method isEqualToString:@"BUSY"] && [@(targetSessionId) isEqualToNumber:self.tryGetSessionId];
}

+ (HTTPRequest*)httpRequestToOpenPortWithSessionId:(int64_t)sessionId {
    return [[HTTPRequest alloc] initUnauthenticatedWithMethod:@"GET"
                                                  andLocation:[NSString stringWithFormat:@"/open/%lld", sessionId]];
}

+ (HTTPRequest*)httpRequestToRingWithSessionId:(int64_t)sessionId {
    return [[HTTPRequest alloc] initWithOTPAuthenticationAndMethod:@"RING"
                                                       andLocation:[NSString stringWithFormat:@"/session/%lld", sessionId]];
}

+ (HTTPRequest*)httpRequestToSignalBusyWithSessionId:(int64_t)sessionId {
    return [[HTTPRequest alloc] initWithOTPAuthenticationAndMethod:@"BUSY"
                                                       andLocation:[NSString stringWithFormat:@"/session/%lld", sessionId]];
}

+ (HTTPRequest*)httpRequestToInitiateToRemoteNumber:(PhoneNumber*)remoteNumber {
    require(remoteNumber != nil);
    
    NSString* formattedRemoteNumber = remoteNumber.toE164;
    NSString* interopVersionInsert = CLAIMED_INTEROP_VERSION_IN_INITIATE_SIGNAL == 0
                                   ? @""
                                   : [NSString stringWithFormat:@"/%d", CLAIMED_INTEROP_VERSION_IN_INITIATE_SIGNAL];
    return [[HTTPRequest alloc] initWithOTPAuthenticationAndMethod:@"GET"
                                                       andLocation:[NSString stringWithFormat:@"/session%@/%@",
                                                                    interopVersionInsert,
                                                                    formattedRemoteNumber]];
}

+ (HTTPRequest*)httpRequestToStartRegistrationOfPhoneNumber {
    return [[HTTPRequest alloc] initWithBasicAuthenticationAndMethod:@"GET"
                                                         andLocation:@"/users/verification"];
}

+ (HTTPRequest*)httpRequestToStartRegistrationOfPhoneNumberWithVoice {
    return [[HTTPRequest alloc] initWithBasicAuthenticationAndMethod:@"GET"
                                                         andLocation:@"/users/verification/voice"];
}

+ (HTTPRequest*)httpRequestToVerifyAccessToPhoneNumberWithChallenge:(NSString*)challenge {
    require(challenge != nil);
    
    PhoneNumber* localPhoneNumber = SGNKeychainUtil.localNumber;
    NSString* query = [NSString stringWithFormat:@"/users/verification/%@", localPhoneNumber.toE164];
    [SGNKeychainUtil generateSignaling];
    
    NSData* signalingCipherKey = SGNKeychainUtil.signalingCipherKey;
    NSData* signalingMacKey = SGNKeychainUtil.signalingMacKey;
    NSData* signalingExtraKeyData = SGNKeychainUtil.signalingCipherKey;
    NSString* encodedSignalingKey = [[@[signalingCipherKey, signalingMacKey, signalingExtraKeyData] concatDatas] encodedAsBase64];
    NSString* body = [@{@"key" : encodedSignalingKey, @"challenge" : challenge} encodedAsJSON];
    
    return [[HTTPRequest alloc] initWithBasicAuthenticationAndMethod:@"PUT"
                                                         andLocation:query
                                                     andOptionalBody:body];
}

+ (HTTPRequest*)httpRequestToRegisterForApnSignalingWithDeviceToken:(NSData*)deviceToken {
    require(deviceToken != nil);
    
    NSString* query = [NSString stringWithFormat:@"/apn/%@", [deviceToken encodedAsHexString]];
    
    return [[HTTPRequest alloc] initWithBasicAuthenticationAndMethod:@"PUT"
                                                         andLocation:query];
}

+ (HTTPRequest*)httpRequestForPhoneNumberDirectoryFilter {
    return [[HTTPRequest alloc] initWithOTPAuthenticationAndMethod:@"GET"
                                                       andLocation:@"/users/directory"];
}

@end
