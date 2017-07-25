//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSAnalytics.h"
#import "AppVersion.h"
#import "TSStorageManager.h"
#import <CocoaLumberjack/CocoaLumberjack.h>
#import <Reachability/Reachability.h>

NS_ASSUME_NONNULL_BEGIN

#if TARGET_IPHONE_SIMULATOR

#define NO_SIGNAL_ANALYTICS

#else

#ifdef DEBUG

// TODO: Disable analytics for debug builds.
//#define NO_SIGNAL_ANALYTICS

#endif

#endif

NSString *const kOWSAnalytics_EventsCollection = @"kOWSAnalytics_EventsCollection";

NSString *const kOWSAnalytics_Collection = @"kOWSAnalytics_Collection";
NSString *const kOWSAnalytics_KeyLaunchCount = @"kOWSAnalytics_KeyLaunchCount";
NSString *const kOWSAnalytics_KeyLaunchCompleteCount = @"kOWSAnalytics_KeyLaunchCompleteCount";

// Percentage of analytics events to discard. 0 <= x <= 100.
const int kOWSAnalytics_DiscardFrequency = 0;

NSString *NSStringForOWSAnalyticsSeverity(OWSAnalyticsSeverity severity)
{
    switch (severity) {
        case OWSAnalyticsSeverityInfo:
            return @"Info";
        case OWSAnalyticsSeverityError:
            return @"Error";
        case OWSAnalyticsSeverityCritical:
            return @"Critical";
    }
}

@interface OWSAnalytics ()

@property (nonatomic, readonly) Reachability *reachability;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@property (atomic) BOOL hasRequestInFlight;

@property (atomic) NSNumber *launchCount;
@property (atomic) NSNumber *launchCompleteCount;

@end

#pragma mark -

@implementation OWSAnalytics

+ (instancetype)sharedInstance
{
    static OWSAnalytics *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initDefault];
    });
    return instance;
}

// We lazy-create the analytics DB connection, so that we can handle
// errors that occur while initializing TSStorageManager.
+ (YapDatabaseConnection *)dbConnection
{
    static YapDatabaseConnection *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        TSStorageManager *storageManager = [TSStorageManager sharedManager];
        OWSAssert(storageManager);
        // Use a newDatabaseConnection so as not to block reads in the launch path.
        instance = storageManager.newDatabaseConnection;
    });
    return instance;
}

- (instancetype)initDefault
{
    self = [super init];

    if (!self) {
        return self;
    }

    _reachability = [Reachability reachabilityForInternetConnection];

    [self observeNotifications];

    OWSSingletonAssert();

    return self;
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityChanged)
                                                 name:kReachabilityChangedNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reachabilityChanged
{
    OWSAssert([NSThread isMainThread]);

    [self tryToSyncEvents];
}

- (void)applicationDidBecomeActive
{
    OWSAssert([NSThread isMainThread]);

    [self tryToSyncEvents];
}

- (void)tryToSyncEvents
{
    dispatch_async(self.serialQueue, ^{
        // Don't try to sync if:
        //
        // * There's no network available.
        // * There's already a sync request in flight.
        if (!self.reachability.isReachable) {
            DDLogVerbose(@"%@ Not reachable", self.tag);
            return;
        }
        if (self.hasRequestInFlight) {
            return;
        }

        __block NSString *firstEventKey = nil;
        __block NSDictionary *firstEventDictionary = nil;
        [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            // Take any event. We don't need to deliver them in any particular order.
            [transaction enumerateKeysInCollection:kOWSAnalytics_EventsCollection
                                        usingBlock:^(NSString *key, BOOL *_Nonnull stop) {
                                            firstEventKey = key;
                                            *stop = YES;
                                        }];
            if (!firstEventKey) {
                return;
            }
            
            firstEventDictionary = [transaction objectForKey:firstEventKey inCollection:kOWSAnalytics_EventsCollection];
            OWSAssert(firstEventDictionary);
            OWSAssert([firstEventDictionary isKindOfClass:[NSDictionary class]]);
        }];

        if (firstEventDictionary) {
            [self sendEvent:firstEventDictionary eventKey:firstEventKey isCritical:NO];
        }
    });
}

- (void)sendEvent:(NSDictionary *)eventDictionary eventKey:(NSString *)eventKey isCritical:(BOOL)isCritical
{
    OWSAssert(eventDictionary);
    OWSAssert(eventKey);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    OWSAssert(dispatch_get_current_queue() == self.serialQueue);
#pragma clang diagnostic pop

    if (isCritical) {
        [self submitEvent:eventDictionary
            eventKey:eventKey
            success:^{
                DDLogDebug(@"%@ sendEvent[critical] succeeded: %@", self.tag, eventKey);
            }
            failure:^{
                DDLogError(@"%@ sendEvent[critical] failed: %@", self.tag, eventKey);
            }];
    } else {
        self.hasRequestInFlight = YES;
        [self submitEvent:eventDictionary
            eventKey:eventKey
            success:^{
                DDLogDebug(@"%@ sendEvent succeeded: %@", self.tag, eventKey);
                dispatch_async(self.serialQueue, ^{
                    self.hasRequestInFlight = NO;

                    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                        // Remove from queue.
                        [transaction removeObjectForKey:eventKey inCollection:kOWSAnalytics_EventsCollection];
                    }];

                    // Wait a second between network requests / retries.
                    dispatch_after(
                        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            [self tryToSyncEvents];
                        });
                });
            }
            failure:^{
                DDLogError(@"%@ sendEvent failed: %@", self.tag, eventKey);
                dispatch_async(self.serialQueue, ^{
                    self.hasRequestInFlight = NO;

                    // Wait a second between network requests / retries.
                    dispatch_after(
                        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            [self tryToSyncEvents];
                        });
                });
            }];
    }
}

- (void)submitEvent:(NSDictionary *)eventDictionary
           eventKey:(NSString *)eventKey
            success:(void (^_Nonnull)())successBlock
            failure:(void (^_Nonnull)())failureBlock
{
    OWSAssert(eventDictionary);
    OWSAssert(eventKey);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    OWSAssert(dispatch_get_current_queue() == self.serialQueue);
#pragma clang diagnostic pop

    DDLogDebug(@"%@ submitting: %@", self.tag, eventKey);

    __block UIBackgroundTaskIdentifier task;
    task = [UIApplication.sharedApplication beginBackgroundTaskWithExpirationHandler:^{
        failureBlock();

        [UIApplication.sharedApplication endBackgroundTask:task];
    }];

    // Until we integrate with an analytics platform, behave as though all event delivery succeeds.
    dispatch_async(self.serialQueue, ^{
        BOOL success = YES;
        if (success) {
            successBlock();
        } else {
            failureBlock();
        }

        [UIApplication.sharedApplication endBackgroundTask:task];
    });
}

- (dispatch_queue_t)serialQueue
{
    static dispatch_queue_t queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("org.whispersystems.analytics.serial", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

- (NSDictionary<NSString *, id> *)eventSuperProperties
{
    NSMutableDictionary<NSString *, id> *result = [NSMutableDictionary new];
    if (AppVersion.instance.firstAppVersion) {
        result[@"app_version_first"] = AppVersion.instance.firstAppVersion;
    }
    if (AppVersion.instance.lastAppVersion) {
        result[@"app_version_last"] = AppVersion.instance.lastAppVersion;
    }
    if (AppVersion.instance.currentAppVersion) {
        result[@"app_version_current"] = AppVersion.instance.currentAppVersion;
    }
    NSNumber *launchCount = self.launchCount;
    if (launchCount) {
        result[@"launch_count"] = @([self orderOfMagnitudeOf:launchCount.longValue]);
    }
    // TODO: Order of magnitude: thread count.
    // TODO: Order of magnitude: total message count.

    return result;
}

- (long)orderOfMagnitudeOf:(long)value
{
    return [OWSAnalytics orderOfMagnitudeOf:value];
}

+ (long)orderOfMagnitudeOf:(long)value
{
    if (value <= 0) {
        return 0;
    }
    return (long)round(pow(10, floor(log10(value))));
}

- (void)addEvent:(NSString *)eventName severity:(OWSAnalyticsSeverity)severity properties:(NSDictionary *)properties
{
    OWSAssert(eventName.length > 0);

    BOOL isError = severity == OWSAnalyticsSeverityError;
    BOOL isCritical = severity == OWSAnalyticsSeverityCritical;

    uint32_t discardValue = arc4random_uniform(101);
    if (!isError && !isCritical && discardValue < kOWSAnalytics_DiscardFrequency) {
        DDLogVerbose(@"Discarding event: %@", eventName);
        return;
    }

#ifndef NO_SIGNAL_ANALYTICS
    void (^addEvent)() = ^{
        // Add super properties.
        NSMutableDictionary *eventProperties = (properties ? [properties mutableCopy] : [NSMutableDictionary new]);
        [eventProperties addEntriesFromDictionary:self.eventSuperProperties];

        NSDictionary *eventDictionary = [eventProperties copy];
        OWSAssert(eventDictionary);
        NSString *eventKey = [NSUUID UUID].UUIDString;
        DDLogDebug(@"%@ enqueuing event: %@", self.tag, eventKey);

        if (isCritical) {
            // Critical events should not be serialized or enqueued - they should be submitted immediately.
            [self sendEvent:eventDictionary eventKey:eventKey isCritical:YES];
        } else {
            // Add to queue.
            [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                const int kMaxQueuedEvents = 5000;
                if ([transaction numberOfKeysInCollection:kOWSAnalytics_EventsCollection] > kMaxQueuedEvents) {
                    DDLogError(@"%@ Event queue overflow.", self.tag);
                    return;
                }

                [transaction setObject:eventDictionary forKey:eventKey inCollection:kOWSAnalytics_EventsCollection];
            }];

            [self tryToSyncEvents];
        }
    };

    if ([self isSeverityAsync:severity]) {
        dispatch_async(self.serialQueue, addEvent);
    } else {
        dispatch_sync(self.serialQueue, addEvent);
    }
#endif
}

+ (void)logEvent:(NSString *)eventName
        severity:(OWSAnalyticsSeverity)severity
      parameters:(nullable NSDictionary *)parameters
        location:(const char *)location
            line:(int)line
{
    [[self sharedInstance] logEvent:eventName severity:severity parameters:parameters location:location line:line];
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
            OWSAssert(0);
            logFlag = DDLogFlagDebug;
            break;
    }

    // Log the event.
    NSString *logString = [NSString stringWithFormat:@"%s:%d %@", location, line, eventName];
    if (!parameters) {
        LOG_MAYBE([self isSeverityAsync:severity], LOG_LEVEL_DEF, logFlag, 0, nil, location, @"%@", logString);
    } else {
        LOG_MAYBE(
            [self isSeverityAsync:severity], LOG_LEVEL_DEF, logFlag, 0, nil, location, @"%@ %@", logString, parameters);
    }
    if (![self isSeverityAsync:severity]) {
        [DDLog flushLog];
    }

    NSMutableDictionary *eventProperties = (parameters ? [parameters mutableCopy] : [NSMutableDictionary new]);
    eventProperties[@"event_location"] = [NSString stringWithFormat:@"%s:%d", location, line];
    [self addEvent:eventName severity:severity properties:eventProperties];
}

- (BOOL)isSeverityAsync:(OWSAnalyticsSeverity)severity
{
    return severity == OWSAnalyticsSeverityCritical;
}

#pragma mark - Logging

+ (void)appLaunchDidBegin
{
    [self.sharedInstance appLaunchDidBegin];
}

- (void)appLaunchDidBegin
{
    OWSProdInfo(@"app_launch");

    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        NSNumber *oldLaunchCount =
            [transaction objectForKey:kOWSAnalytics_KeyLaunchCount inCollection:kOWSAnalytics_Collection];
        NSNumber *newLaunchCount = @(oldLaunchCount.longValue + 1);
        self.launchCount = newLaunchCount;

        NSNumber *oldLaunchCompleteCount =
            [transaction objectForKey:kOWSAnalytics_KeyLaunchCompleteCount inCollection:kOWSAnalytics_Collection];
        self.launchCompleteCount = @(oldLaunchCompleteCount.longValue);
    }];
    [self.dbConnection
        asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            [transaction setObject:self.launchCount
                            forKey:kOWSAnalytics_KeyLaunchCount
                      inCollection:kOWSAnalytics_Collection];
        }];
}

+ (void)appLaunchDidComplete
{
    [self.sharedInstance appLaunchDidComplete];
}

- (void)appLaunchDidComplete
{
    OWSProdInfo(@"app_launch_complete");

    self.launchCompleteCount = @(self.launchCompleteCount.longValue + 1);

    [self.dbConnection
        asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            [transaction setObject:self.launchCompleteCount
                            forKey:kOWSAnalytics_KeyLaunchCompleteCount
                      inCollection:kOWSAnalytics_Collection];
        }];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
