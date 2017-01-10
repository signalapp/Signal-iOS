//
//  OWSAnalytics.h
//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

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
// parameters: Optional.
//             If non-nil, the keys should all be non-empty NSStrings.
//             Values should be NSStrings or NSNumbers.
+ (void)logEvent:(NSString *)description
        severity:(OWSAnalyticsSeverity)severity
      parameters:(NSDictionary *)parameters
        location:(const char *)location;

@end

#define OWSAnalyticsLogEvent(severityLevel, frmt, ...)                                                                 \
    [OWSAnalytics logEvent:[NSString stringWithFormat:frmt, ##__VA_ARGS__]                                             \
                  severity:severityLevel                                                                               \
                parameters:nil                                                                                         \
                  location:__PRETTY_FUNCTION__];

#define OWSAnalyticsLogEventWithParameters(severityLevel, frmt, params)                                                \
    [OWSAnalytics logEvent:frmt severity:severityLevel parameters:params location:__PRETTY_FUNCTION__];

#define OWSAnalyticsDebug(frmt, ...) OWSAnalyticsLogEvent(OWSAnalyticsSeverityDebug, frmt, ##__VA_ARGS__)
#define OWSAnalyticsDebugWithParameters(description, params)                                                           \
    OWSAnalyticsLogEventWithParameters(OWSAnalyticsSeverityDebug, description, params)

#define OWSAnalyticsInfo(frmt, ...) OWSAnalyticsLogEvent(OWSAnalyticsSeverityInfo, frmt, ##__VA_ARGS__)
#define OWSAnalyticsInfoWithParameters(description, params)                                                            \
    OWSAnalyticsLogEventWithParameters(OWSAnalyticsSeverityInfo, description, params)

#define OWSAnalyticsWarn(frmt, ...) OWSAnalyticsLogEvent(OWSAnalyticsSeverityWarn, frmt, ##__VA_ARGS__)
#define OWSAnalyticsWarnWithParameters(description, params)                                                            \
    OWSAnalyticsLogEventWithParameters(OWSAnalyticsSeverityWarn, description, params)

#define OWSAnalyticsError(frmt, ...) OWSAnalyticsLogEvent(OWSAnalyticsSeverityError, frmt, ##__VA_ARGS__)
#define OWSAnalyticsErrorWithParameters(description, params)                                                           \
    OWSAnalyticsLogEventWithParameters(OWSAnalyticsSeverityError, description, params)

#define OWSAnalyticsCritical(frmt, ...) OWSAnalyticsLogEvent(OWSAnalyticsSeverityCritical, frmt, ##__VA_ARGS__)
#define OWSAnalyticsCriticalWithParameters(description, params)                                                        \
    OWSAnalyticsLogEventWithParameters(OWSAnalyticsSeverityCritical, description, params)
