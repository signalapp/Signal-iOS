#import <Foundation/Foundation.h>
#import "HttpManager.h"
#import "HttpRequestUtil.h"

#define SIGNAL_STATUS_CODE_STALE_SESSION 404
#define SIGNAL_STATUS_CODE_NO_SUCH_USER 404
#define SIGNAL_STATUS_CODE_SERVER_MESSAGE 402
#define SIGNAL_STATUS_CODE_LOGIN_FAILED 401

@interface HttpRequest (SignalUtil)

- (bool)isKeepAlive;

- (bool)isRingingForSession:(int64_t)targetSessionId;

- (bool)isHangupForSession:(int64_t)targetSessionId;

- (bool)isBusyForSession:(int64_t)targetSessionId;

+ (HttpRequest *)httpRequestToOpenPortWithSessionId:(int64_t)sessionId;

+ (HttpRequest *)httpRequestToInitiateToRemoteNumber:(PhoneNumber *)remoteNumber;

+ (HttpRequest *)httpRequestToRingWithSessionId:(int64_t)sessionId;

+ (HttpRequest *)httpRequestToSignalBusyWithSessionId:(int64_t)sessionId;

+ (HttpRequest *)httpRequestToStartRegistrationOfPhoneNumber;

+ (HttpRequest *)httpRequestToStartRegistrationOfPhoneNumberWithVoice;

+ (HttpRequest *)httpRequestToVerifyAccessToPhoneNumberWithChallenge:(NSString *)challenge;

+ (HttpRequest *)httpRequestToRegisterForApnSignalingWithDeviceToken:(NSData *)deviceToken;

+ (HttpRequest *)httpRequestForPhoneNumberDirectoryFilter;

@end
