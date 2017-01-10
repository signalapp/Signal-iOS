//
//  OWSAnalytics.m
//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <CocoaLumberjack/CocoaLumberjack.h>

#import "OWSAnalytics.h"

@implementation OWSAnalytics

+ (instancetype)sharedInstance
{
    static OWSAnalytics *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [self new];
        // TODO: If we ever log these events to disk,
        // we may want to protect these file(s) like TSStorageManager.
    });
    return instance;
}

+ (void)logEvent:(NSString *)description
        severity:(OWSAnalyticsSeverity)severity
      parameters:(NSDictionary *)parameters
        location:(const char *)location
{

    [[self sharedInstance] logEvent:description severity:severity parameters:parameters location:location];
}

- (void)logEvent:(NSString *)description
        severity:(OWSAnalyticsSeverity)severity
      parameters:(NSDictionary *)parameters
        location:(const char *)location
{

    DDLogFlag logFlag;
    BOOL async = YES;
    switch (severity) {
        case OWSAnalyticsSeverityDebug:
            logFlag = DDLogFlagDebug;
            break;
        case OWSAnalyticsSeverityInfo:
            logFlag = DDLogFlagInfo;
            break;
        case OWSAnalyticsSeverityWarn:
            logFlag = DDLogFlagWarning;
            break;
        case OWSAnalyticsSeverityError:
            logFlag = DDLogFlagError;
            async = NO;
            break;
        case OWSAnalyticsSeverityCritical:
            logFlag = DDLogFlagError;
            async = NO;
            break;
        default:
            OWSAssert(0);
            logFlag = DDLogFlagDebug;
            break;
    }

    // Log the event.
    if (!parameters) {
        LOG_MAYBE(async, LOG_LEVEL_DEF, logFlag, 0, nil, location, @"%@", description);
    } else {
        LOG_MAYBE(async, LOG_LEVEL_DEF, logFlag, 0, nil, location, @"%@ %@", description, parameters);
    }

    // Do nothing.  We don't yet serialize or transmit analytics events.
}

@end
