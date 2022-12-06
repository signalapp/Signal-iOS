//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSAnalytics.h"
#import <CocoaLumberjack/CocoaLumberjack.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSAnalytics

+ (instancetype)shared
{
    static OWSAnalytics *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initDefault];
    });
    return instance;
}

- (instancetype)initDefault
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    return self;
}

+ (void)logEvent:(NSString *)eventName
        severity:(OWSAnalyticsSeverity)severity
      parameters:(nullable NSDictionary *)parameters
        location:(const char *)location
            line:(int)line
{
    [[self shared] logEvent:eventName severity:severity parameters:parameters location:location line:line];
}

- (void)logEvent:(NSString *)eventName
        severity:(OWSAnalyticsSeverity)severity
      parameters:(nullable NSDictionary *)parameters
        location:(const char *)location
            line:(int)line
{
    DDLogFlag logFlag;
    switch (severity) {
        case OWSAnalyticsSeverityInfo:
            logFlag = DDLogFlagInfo;
            break;
        case OWSAnalyticsSeverityError:
            logFlag = DDLogFlagError;
            break;
        case OWSAnalyticsSeverityCritical:
            logFlag = DDLogFlagError;
            break;
        default:
            OWSFailDebug(@"Unknown severity.");
            logFlag = DDLogFlagDebug;
            break;
    }

    // Log the event.
    NSString *logString = [NSString stringWithFormat:@"%s:%d %@", location, line, eventName];
    if (!parameters) {
        LOG_MAYBE([self shouldReportAsync:severity], LOG_LEVEL_DEF, logFlag, 0, nil, location, @"%@", logString);
    } else {
        LOG_MAYBE([self shouldReportAsync:severity],
            LOG_LEVEL_DEF,
            logFlag,
            0,
            nil,
            location,
            @"%@ %@",
            logString,
            parameters);
    }
    if (![self shouldReportAsync:severity]) {
        OWSLogFlush();
    }
}

- (BOOL)shouldReportAsync:(OWSAnalyticsSeverity)severity
{
    return severity != OWSAnalyticsSeverityCritical;
}

#pragma mark - Logging

+ (void)appLaunchDidBegin
{
    [self.shared appLaunchDidBegin];
}

- (void)appLaunchDidBegin
{
    OWSProdInfo([OWSAnalyticsEvents appLaunch]);
}

@end

NS_ASSUME_NONNULL_END
