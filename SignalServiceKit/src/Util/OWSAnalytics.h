//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

// TODO: We probably don't need all of these levels.
typedef NS_ENUM(NSUInteger, OWSAnalyticsSeverity) {
    OWSAnalyticsSeverityDebug = 0,
    OWSAnalyticsSeverityInfo = 1,
    OWSAnalyticsSeverityWarn = 2,
    OWSAnalyticsSeverityError = 3,
    // I suspect we'll stage the development of our analytics,
    // initially building only a minimal solution: an endpoint which
    // ignores most requests, and sends only the highest-severity
    // events as email to developers.
    //
    // This "critical" level of severity is intended for that purpose (for now).
    //
    // We might want to have an additional level of severity for
    // critical (crashing) bugs that occur during app startup. These
    // events should be sent to the service immediately and the app
    // should block until that request completes.
    OWSAnalyticsSeverityCritical = 4,
    OWSAnalyticsSeverityOff = 5
};

// This is a placeholder. We don't yet serialize or transmit analytics events.
//
// If/when we take this on, we'll want to develop a solution that can be used
// report user activity - especially serious bugs - without compromising user
// privacy in any way.  We must _never_ include any identifying information.
@interface OWSAnalytics : NSObject

// description: A non-empty string without any leading whitespace.
//              This should conform to our analytics event naming conventions.
//              "category_event_name", e.g. "database_error_no_database_file_found".
// parameters: Optional.
//             If non-nil, the keys should all be non-empty NSStrings.
//             Values should be NSStrings or NSNumbers.
+ (void)logEvent:(NSString *)eventName
        severity:(OWSAnalyticsSeverity)severity
      parameters:(nullable NSDictionary *)parameters
        location:(const char *)location
            line:(int)line;

+ (void)appLaunchDidBegin;

+ (void)appLaunchDidComplete;

@end

typedef NSDictionary<NSString *, id> *_Nonnull (^OWSProdAssertParametersBlock)();

#define kOWSProdAssertParameterDescription @"description"
#define kOWSProdAssertParameterNSErrorDomain @"nserror_domain"
#define kOWSProdAssertParameterNSErrorCode @"nserror_code"
#define kOWSProdAssertParameterNSErrorDescription @"nserror_description"
#define kOWSProdAssertParameterNSExceptionName @"nsexception_name"
#define kOWSProdAssertParameterNSExceptionReason @"nsexception_reason"
#define kOWSProdAssertParameterNSExceptionClassName @"nsexception_classname"

// These methods should be used to assert errors for which we want to fire analytics events.
//
// In production, returns __Value, the assert value, so that we can handle this case.
// In debug builds, asserts.
//
// parametersBlock is of type OWSProdAssertParametersBlock.
// The "C" variants (e.g. OWSProdAssert() vs. OWSProdCAssert() should be used in free functions,
// where there is no self.
//
#define OWSProdAssertWParamsTemplate(__value, __analyticsEventName, __parametersBlock, __assertMacro)                  \
    {                                                                                                                  \
        if (!(BOOL)(__value)) {                                                                                        \
            NSDictionary<NSString *, id> *__eventParameters = (__parametersBlock ? __parametersBlock() : nil);         \
            [DDLog flushLog];                                                                                          \
            [OWSAnalytics logEvent:__analyticsEventName                                                                \
                          severity:OWSAnalyticsSeverityError                                                           \
                        parameters:__eventParameters                                                                   \
                          location:__PRETTY_FUNCTION__                                                                 \
                              line:__LINE__];                                                                          \
        }                                                                                                              \
        __assertMacro(__value);                                                                                        \
        return (BOOL)(__value);                                                                                        \
    }

#define OWSProdAssertWParams(__value, __analyticsEventName, __parametersBlock)                                         \
    OWSProdAssertWParamsTemplate(__value, __analyticsEventName, __parametersBlock, OWSAssert)

#define OWSProdCAssertWParams(__value, __analyticsEventName, __parametersBlock)                                        \
    OWSProdAssertWParamsTemplate(__value, __analyticsEventName, __parametersBlock, OWSCAssert)

#define OWSProdAssert(__value, __analyticsEventName) OWSProdAssertWParams(__value, __analyticsEventName, nil)

#define OWSProdCAssert(__value, __analyticsEventName) OWSProdCAssertWParams(__value, __analyticsEventName, nil)

#define OWSProdFailWParamsTemplate(__analyticsEventName, __parametersBlock, __failMacro)                               \
    {                                                                                                                  \
        NSDictionary<NSString *, id> *__eventParameters                                                                \
            = (__parametersBlock ? ((OWSProdAssertParametersBlock)__parametersBlock)() : nil);                         \
        [OWSAnalytics logEvent:__analyticsEventName                                                                    \
                      severity:OWSAnalyticsSeverityCritical                                                            \
                    parameters:__eventParameters                                                                       \
                      location:__PRETTY_FUNCTION__                                                                     \
                          line:__LINE__];                                                                              \
        __failMacro(__analyticsEventName);                                                                             \
    }

#define OWSProdFailWParams(__analyticsEventName, __parametersBlock)                                                    \
    OWSProdFailWParamsTemplate(__analyticsEventName, __parametersBlock, OWSFail)
#define OWSProdCFailWParams(__analyticsEventName, __parametersBlock)                                                   \
    OWSProdFailWParamsTemplate(__analyticsEventName, __parametersBlock, OWSCFail)

#define OWSProdFail(__analyticsEventName) OWSProdFailWParams(__analyticsEventName, nil)

#define OWSProdCFail(__analyticsEventName) OWSProdCFailWParams(__analyticsEventName, nil)

#define AnalyticsParametersFromNSError(__nserror)                                                                      \
    ^{                                                                                                                 \
        return (@{                                                                                                     \
            kOWSProdAssertParameterNSErrorDomain : __nserror.domain,                                                   \
            kOWSProdAssertParameterNSErrorCode : @(__nserror.code),                                                    \
            kOWSProdAssertParameterNSErrorDescription : __nserror.description,                                         \
        });                                                                                                            \
    }

#define AnalyticsParametersFromNSException(__exception)                                                                \
    ^{                                                                                                                 \
        return (@{                                                                                                     \
            kOWSProdAssertParameterNSExceptionName : __exception.name,                                                 \
            kOWSProdAssertParameterNSExceptionReason : __exception.reason,                                             \
            kOWSProdAssertParameterNSExceptionClassName : NSStringFromClass([__exception class]),                      \
        });                                                                                                            \
    }

#define OWSProdFailWNSError(__analyticsEventName, __nserror)                                                           \
    OWSProdFailWParams(__analyticsEventName, AnalyticsParametersFromNSError(__nserror))

#define OWSProdFailWNSException(__analyticsEventName, __exception)                                                     \
    OWSProdFailWParams(__analyticsEventName, AnalyticsParametersFromNSException(__exception))

#define OWSProdEventWParams(__severityLevel, __analyticsEventName, __parametersBlock)                                  \
    {                                                                                                                  \
        NSDictionary<NSString *, id> *__eventParameters                                                                \
            = (__parametersBlock ? ((OWSProdAssertParametersBlock)__parametersBlock)() : nil);                         \
        [OWSAnalytics logEvent:__analyticsEventName                                                                    \
                      severity:OWSAnalyticsSeverityCritical                                                            \
                    parameters:__eventParameters                                                                       \
                      location:__PRETTY_FUNCTION__                                                                     \
                          line:__LINE__];                                                                              \
    }

#define OWSProdErrorWParams(__analyticsEventName, __parametersBlock)                                                   \
    OWSProdEventWParams(OWSAnalyticsSeverityCritical, __analyticsEventName, __parametersBlock)

#define OWSProdError(__analyticsEventName) OWSProdEventWParams(OWSAnalyticsSeverityCritical, __analyticsEventName, nil)

#define OWSProdInfoWParams(__analyticsEventName, __parametersBlock)                                                    \
    OWSProdEventWParams(OWSAnalyticsSeverityInfo, __analyticsEventName, __parametersBlock)

#define OWSProdInfo(__analyticsEventName) OWSProdEventWParams(OWSAnalyticsSeverityInfo, __analyticsEventName, nil)

#define OWSProdCFail(__analyticsEventName) OWSProdCFailWParams(__analyticsEventName, nil)

#define OWSProdErrorWNSError(__analyticsEventName, __nserror)                                                          \
    OWSProdErrorWParams(__analyticsEventName, AnalyticsParametersFromNSError(__nserror))

#define OWSProdErrorWNSException(__analyticsEventName, __exception)                                                    \
    OWSProdErrorWParams(__analyticsEventName, AnalyticsParametersFromNSException(__exception))

NS_ASSUME_NONNULL_END
