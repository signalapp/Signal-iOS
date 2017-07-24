//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

// TODO: We probably don't need all of these levels.
typedef NS_ENUM(NSUInteger, OWSAnalyticsSeverity) {
    // Info events are routine.
    //
    // It's safe to discard a large fraction of these events.
    OWSAnalyticsSeverityInfo = 1,
    // Error events should never be discarded.
    OWSAnalyticsSeverityError = 3,
    // Critical events should never be discarded.
    //
    // Additionally, to avoid losing critical events they should
    // be persisted synchronously.
    OWSAnalyticsSeverityCritical = 4
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

+ (long)orderOfMagnitudeOf:(long)value;

@end

typedef NSDictionary<NSString *, id> *_Nonnull (^OWSProdAssertParametersBlock)();

#define kOWSAnalyticsParameterDescription @"description"
#define kOWSAnalyticsParameterNSErrorDomain @"nserror_domain"
#define kOWSAnalyticsParameterNSErrorCode @"nserror_code"
#define kOWSAnalyticsParameterNSErrorDescription @"nserror_description"
#define kOWSAnalyticsParameterNSExceptionName @"nsexception_name"
#define kOWSAnalyticsParameterNSExceptionReason @"nsexception_reason"
#define kOWSAnalyticsParameterNSExceptionClassName @"nsexception_classname"

// We don't include the error description because it may have PII.
#define AnalyticsParametersFromNSError(__nserror)                                                                      \
    ^{                                                                                                                 \
        return (@{                                                                                                     \
            kOWSAnalyticsParameterNSErrorDomain : (__nserror.domain ?: @"unknown"),                                    \
            kOWSAnalyticsParameterNSErrorCode : @(__nserror.code),                                                     \
        });                                                                                                            \
    }

#define AnalyticsParametersFromNSException(__exception)                                                                \
    ^{                                                                                                                 \
        return (@{                                                                                                     \
            kOWSAnalyticsParameterNSExceptionName : (__exception.name ?: @"unknown"),                                  \
            kOWSAnalyticsParameterNSExceptionReason : (__exception.reason ?: @"unknown"),                              \
            kOWSAnalyticsParameterNSExceptionClassName :                                                               \
                (__exception ? NSStringFromClass([__exception class]) : @"unknown"),                                   \
        });                                                                                                            \
    }

// These methods should be used to assert errors for which we want to fire analytics events.
//
// In production, returns __Value, the assert value, so that we can handle this case.
// In debug builds, asserts.
//
// parametersBlock is of type OWSProdAssertParametersBlock.
// The "C" variants (e.g. OWSProdAssert() vs. OWSProdCAssert() should be used in free functions,
// where there is no self. They can also be used in blocks to avoid capturing a reference to self.
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

// The debug logs can be more verbose than the analytics events.
//
// In this case `debugDescription` is valuable enough to
// log but too dangerous to include in the analytics event.
#define OWSProdFailWNSError(__analyticsEventName, __nserror)                                                           \
    {                                                                                                                  \
        DDLogError(@"%s:%d %@: %@", __PRETTY_FUNCTION__, __LINE__, __analyticsEventName, __nserror.debugDescription);  \
        OWSProdFailWParams(__analyticsEventName, AnalyticsParametersFromNSError(__nserror))                            \
    }

// The debug logs can be more verbose than the analytics events.
//
// In this case `exception` is valuable enough to
// log but too dangerous to include in the analytics event.
#define OWSProdFailWNSException(__analyticsEventName, __exception)                                                     \
    {                                                                                                                  \
        DDLogError(@"%s:%d %@: %@", __PRETTY_FUNCTION__, __LINE__, __analyticsEventName, __exception);                 \
        OWSProdFailWParams(__analyticsEventName, AnalyticsParametersFromNSException(__exception))                      \
    }

#define OWSProdCFail(__analyticsEventName) OWSProdCFailWParams(__analyticsEventName, nil)

#define OWSProdEventWParams(__severityLevel, __analyticsEventName, __parametersBlock)                                  \
    {                                                                                                                  \
        NSDictionary<NSString *, id> *__eventParameters                                                                \
            = (__parametersBlock ? ((OWSProdAssertParametersBlock)__parametersBlock)() : nil);                         \
        [OWSAnalytics logEvent:__analyticsEventName                                                                    \
                      severity:__severityLevel                                                                         \
                    parameters:__eventParameters                                                                       \
                      location:__PRETTY_FUNCTION__                                                                     \
                          line:__LINE__];                                                                              \
    }

#pragma mark - Info Events

#define OWSProdInfoWParams(__analyticsEventName, __parametersBlock)                                                    \
    OWSProdEventWParams(OWSAnalyticsSeverityInfo, __analyticsEventName, __parametersBlock)

#define OWSProdInfo(__analyticsEventName) OWSProdEventWParams(OWSAnalyticsSeverityInfo, __analyticsEventName, nil)

#pragma mark - Error Events

#define OWSProdErrorWParams(__analyticsEventName, __parametersBlock)                                                   \
    OWSProdEventWParams(OWSAnalyticsSeverityError, __analyticsEventName, __parametersBlock)

#define OWSProdError(__analyticsEventName) OWSProdEventWParams(OWSAnalyticsSeverityError, __analyticsEventName, nil)

// The debug logs can be more verbose than the analytics events.
//
// In this case `debugDescription` is valuable enough to
// log but too dangerous to include in the analytics event.
#define OWSProdErrorWNSError(__analyticsEventName, __nserror)                                                          \
    {                                                                                                                  \
        DDLogError(@"%s:%d %@: %@", __PRETTY_FUNCTION__, __LINE__, __analyticsEventName, __nserror.debugDescription);  \
        OWSProdErrorWParams(__analyticsEventName, AnalyticsParametersFromNSError(__nserror))                           \
    }

// The debug logs can be more verbose than the analytics events.
//
// In this case `exception` is valuable enough to
// log but too dangerous to include in the analytics event.
#define OWSProdErrorWNSException(__analyticsEventName, __exception)                                                    \
    {                                                                                                                  \
        DDLogError(@"%s:%d %@: %@", __PRETTY_FUNCTION__, __LINE__, __analyticsEventName, __exception);                 \
        OWSProdErrorWParams(__analyticsEventName, AnalyticsParametersFromNSException(__exception))                     \
    }

#pragma mark - Critical Events

#define OWSProdCriticalWParams(__analyticsEventName, __parametersBlock)                                                \
    OWSProdEventWParams(OWSAnalyticsSeverityCritical, __analyticsEventName, __parametersBlock)

#define OWSProdCritical(__analyticsEventName)                                                                          \
    OWSProdEventWParams(OWSAnalyticsSeverityCritical, __analyticsEventName, nil)

#define OWSProdCriticalWNSError(__analyticsEventName, __nserror)                                                       \
    {                                                                                                                  \
        DDLogError(@"%s:%d %@: %@", __PRETTY_FUNCTION__, __LINE__, __analyticsEventName, __nserror.debugDescription);  \
        OWSProdCriticalWParams(__analyticsEventName, AnalyticsParametersFromNSError(__nserror))                        \
    }

// The debug logs can be more verbose than the analytics events.
//
// In this case `exception` is valuable enough to
// log but too dangerous to include in the analytics event.
#define OWSProdCriticalWNSException(__analyticsEventName, __exception)                                                 \
    {                                                                                                                  \
        DDLogError(@"%s:%d %@: %@", __PRETTY_FUNCTION__, __LINE__, __analyticsEventName, __exception);                 \
        OWSProdCriticalWParams(__analyticsEventName, AnalyticsParametersFromNSException(__exception))                  \
    }

NS_ASSUME_NONNULL_END
