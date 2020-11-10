//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSAnalyticsEvents.h"

NS_ASSUME_NONNULL_BEGIN

// TODO: We probably don't need all of these levels.
typedef NS_ENUM(NSUInteger, OWSAnalyticsSeverity) {
    // Info events are routine.
    //
    // It's safe to discard a large fraction of these events.
    OWSAnalyticsSeverityInfo = 1,
    // Error events should never be discarded.
    OWSAnalyticsSeverityError = 3,
    // Critical events are special.  They are submitted immediately
    // and not persisted, since the database may not be working.
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

+ (long)orderOfMagnitudeOf:(long)value;

@end

typedef NSDictionary<NSString *, id> *_Nonnull (^OWSProdAssertParametersBlock)(void);

// These methods should be used to assert errors for which we want to fire analytics events.
//
// In production, returns __Value, the assert value, so that we can handle this case.
// In debug builds, asserts.
//
// parametersBlock is of type OWSProdAssertParametersBlock.
// The "C" variants (e.g. OWSProdAssert() vs. OWSProdCAssert() should be used in free functions,
// where there is no self. They can also be used in blocks to avoid capturing a reference to self.
#define OWSProdAssertWParamsTemplate(__value, __eventName, __parametersBlock, __assertMacro)                           \
    {                                                                                                                  \
        if (!(BOOL)(__value)) {                                                                                        \
            NSDictionary<NSString *, id> *__eventParameters = (__parametersBlock ? __parametersBlock() : nil);         \
            [DDLog flushLog];                                                                                          \
            [OWSAnalytics logEvent:__eventName                                                                         \
                          severity:OWSAnalyticsSeverityError                                                           \
                        parameters:__eventParameters                                                                   \
                          location:__PRETTY_FUNCTION__                                                                 \
                              line:__LINE__];                                                                          \
        }                                                                                                              \
        __assertMacro(__value);                                                                                        \
        return (BOOL)(__value);                                                                                        \
    }

#define OWSProdAssertWParams(__value, __eventName, __parametersBlock)                                                  \
    OWSProdAssertWParamsTemplate(__value, __eventName, __parametersBlock, OWSAssert)

#define OWSProdCAssertWParams(__value, __eventName, __parametersBlock)                                                 \
    OWSProdAssertWParamsTemplate(__value, __eventName, __parametersBlock, OWSCAssert)

#define OWSProdAssert(__value, __eventName) OWSProdAssertWParams(__value, __eventName, nil)

#define OWSProdCAssert(__value, __eventName) OWSProdCAssertWParams(__value, __eventName, nil)

#define OWSProdFailWParamsTemplate(__eventName, __parametersBlock, __failMacro)                                        \
    {                                                                                                                  \
        NSDictionary<NSString *, id> *__eventParameters                                                                \
            = (__parametersBlock ? ((OWSProdAssertParametersBlock)__parametersBlock)() : nil);                         \
        [OWSAnalytics logEvent:__eventName                                                                             \
                      severity:OWSAnalyticsSeverityCritical                                                            \
                    parameters:__eventParameters                                                                       \
                      location:__PRETTY_FUNCTION__                                                                     \
                          line:__LINE__];                                                                              \
        __failMacro(__eventName);                                                                                      \
    }

#define OWSProdFailWParams(__eventName, __parametersBlock)                                                             \
    OWSProdFailWParamsTemplate(__eventName, __parametersBlock, OWSFailNoFormat)
#define OWSProdCFailWParams(__eventName, __parametersBlock)                                                            \
    OWSProdFailWParamsTemplate(__eventName, __parametersBlock, OWSCFailNoFormat)

#define OWSProdFail(__eventName) OWSProdFailWParams(__eventName, nil)

#define OWSProdCFail(__eventName) OWSProdCFailWParams(__eventName, nil)

#define OWSProdCFail(__eventName) OWSProdCFailWParams(__eventName, nil)

#define OWSProdEventWParams(__severityLevel, __eventName, __parametersBlock)                                           \
    {                                                                                                                  \
        NSDictionary<NSString *, id> *__eventParameters                                                                \
            = (__parametersBlock ? ((OWSProdAssertParametersBlock)__parametersBlock)() : nil);                         \
        [OWSAnalytics logEvent:__eventName                                                                             \
                      severity:__severityLevel                                                                         \
                    parameters:__eventParameters                                                                       \
                      location:__PRETTY_FUNCTION__                                                                     \
                          line:__LINE__];                                                                              \
    }

#pragma mark - Info Events

#define OWSProdInfoWParams(__eventName, __parametersBlock)                                                             \
    OWSProdEventWParams(OWSAnalyticsSeverityInfo, __eventName, __parametersBlock)

#define OWSProdInfo(__eventName) OWSProdEventWParams(OWSAnalyticsSeverityInfo, __eventName, nil)

#pragma mark - Error Events

#define OWSProdErrorWParams(__eventName, __parametersBlock)                                                            \
    OWSProdEventWParams(OWSAnalyticsSeverityError, __eventName, __parametersBlock)

#define OWSProdError(__eventName) OWSProdEventWParams(OWSAnalyticsSeverityError, __eventName, nil)

#pragma mark - Critical Events

#define OWSProdCriticalWParams(__eventName, __parametersBlock)                                                         \
    OWSProdEventWParams(OWSAnalyticsSeverityCritical, __eventName, __parametersBlock)

#define OWSProdCritical(__eventName) OWSProdEventWParams(OWSAnalyticsSeverityCritical, __eventName, nil)

#pragma mark - OWSMessageManager macros
// Defined here rather than in OWSMessageManager so that our analytic event extraction script
// can properly detect the event names.
//
// The debug logs can be more verbose than the analytics events.
//
// In this case `descriptionForEnvelope` is valuable enough to
// log but too dangerous to include in the analytics event.
#define OWSProdErrorWEnvelope(__analyticsEventName, __envelope)                                                        \
    {                                                                                                                  \
        OWSLogError(@"%s:%d %@: %@",                                                                                   \
            __PRETTY_FUNCTION__,                                                                                       \
            __LINE__,                                                                                                  \
            __analyticsEventName,                                                                                      \
            [self descriptionForEnvelope:__envelope]);                                                                 \
        OWSProdError(__analyticsEventName)                                                                             \
    }

#define OWSProdInfoWEnvelope(__analyticsEventName, __envelope)                                                         \
    {                                                                                                                  \
        OWSLogInfo(@"%s:%d %@: %@",                                                                                    \
            __PRETTY_FUNCTION__,                                                                                       \
            __LINE__,                                                                                                  \
            __analyticsEventName,                                                                                      \
            [self descriptionForEnvelope:__envelope]);                                                                 \
        OWSProdInfo(__analyticsEventName)                                                                              \
    }

NS_ASSUME_NONNULL_END
