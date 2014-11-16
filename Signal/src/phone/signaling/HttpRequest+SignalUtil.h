#import <Foundation/Foundation.h>
#import "HTTPManager.h"
#import "HTTPRequest+Util.h"
#import "PhoneNumberDirectoryFilter.h"

#define SIGNAL_STATUS_CODE_STALE_SESSION 404
#define SIGNAL_STATUS_CODE_NO_SUCH_USER 404
#define SIGNAL_STATUS_CODE_SERVER_MESSAGE 402
#define SIGNAL_STATUS_CODE_LOGIN_FAILED 401

@interface HTTPRequest (SignalUtil)

- (bool)isKeepAlive;

- (bool)isRingingForSession:(int64_t)targetSessionId;

- (bool)isHangupForSession:(int64_t)targetSessionId;

- (bool)isBusyForSession:(int64_t)targetSessionId;

+ (HTTPRequest*)httpRequestToOpenPortWithSessionId:(int64_t)sessionId;

+ (HTTPRequest*)httpRequestToInitiateToRemoteNumber:(PhoneNumber*)remoteNumber;

+ (HTTPRequest*)httpRequestToRingWithSessionId:(int64_t)sessionId;

+ (HTTPRequest*)httpRequestToSignalBusyWithSessionId:(int64_t)sessionId;

+ (HTTPRequest*)httpRequestToStartRegistrationOfPhoneNumber;

+ (HTTPRequest*)httpRequestToStartRegistrationOfPhoneNumberWithVoice;

+ (HTTPRequest*)httpRequestToVerifyAccessToPhoneNumberWithChallenge:(NSString*)challenge;

+ (HTTPRequest*)httpRequestToRegisterForApnSignalingWithDeviceToken:(NSData*)deviceToken;

+ (HTTPRequest*)httpRequestForPhoneNumberDirectoryFilter;

@end
