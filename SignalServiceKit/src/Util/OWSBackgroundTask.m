//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackgroundTask.h"
#import "AppContext.h"
#import "NSTimer+OWS.h"
#import "Threading.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^BackgroundTaskExpirationBlock)(void);
typedef NSNumber *OWSTaskId;

// This class can be safely accessed and used from any thread.
@interface OWSBackgroundTaskManager ()

// This property should only be accessed while synchronized on this instance.
@property (nonatomic) UIBackgroundTaskIdentifier backgroundTaskId;

// This property should only be accessed while synchronized on this instance.
@property (nonatomic) NSMutableDictionary<OWSTaskId, BackgroundTaskExpirationBlock> *expirationMap;

// This property should only be accessed while synchronized on this instance.
@property (nonatomic) unsigned long long idCounter;

// Note that this flag is set a little early in "will resign active".
//
// This property should only be accessed while synchronized on this instance.
@property (nonatomic) BOOL isAppActive;

// We use this timer to provide continuity and reduce churn,
// so that if one OWSBackgroundTask ends right before another
// begins, we use a single uninterrupted background that
// spans their lifetimes.
//
// This property should only be accessed while synchronized on this instance.
@property (nonatomic, nullable) NSTimer *continuityTimer;

@end

#pragma mark -

@implementation OWSBackgroundTaskManager

+ (instancetype)sharedManager
{
    static OWSBackgroundTaskManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
}

- (instancetype)initDefault
{
    OWSAssertIsOnMainThread();

    self = [super init];

    if (!self) {
        return self;
    }

    self.backgroundTaskId = UIBackgroundTaskInvalid;
    self.expirationMap = [NSMutableDictionary new];
    self.idCounter = 0;
    self.isAppActive = CurrentAppContext().isMainAppAndActive;

    OWSSingletonAssert();

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)observeNotifications
{
    if (!CurrentAppContext().isMainApp) {
        return;
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:OWSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:OWSApplicationWillResignActiveNotification
                                               object:nil];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    OWSAssertIsOnMainThread();

    @synchronized(self)
    {
        self.isAppActive = YES;

        [self ensureBackgroundTaskState];
    }
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    OWSAssertIsOnMainThread();

    @synchronized(self)
    {
        self.isAppActive = NO;

        [self ensureBackgroundTaskState];
    }
}

// This method registers a new task with this manager.  We only bother
// requesting a background task from iOS if the app is inactive (or about
// to become inactive), so this will often not start a background task.
//
// Returns nil if adding this task _should have_ started a
// background task, but the background task couldn't be begun.
// In that case expirationBlock will not be called.
- (nullable OWSTaskId)addTaskWithExpirationBlock:(BackgroundTaskExpirationBlock)expirationBlock
{
    OWSAssertDebug(expirationBlock);

    OWSTaskId _Nullable taskId;

    @synchronized(self)
    {
        self.idCounter = self.idCounter + 1;
        taskId = @(self.idCounter);
        self.expirationMap[taskId] = expirationBlock;

        if (![self ensureBackgroundTaskState]) {
            [self.expirationMap removeObjectForKey:taskId];
            return nil;
        }

        [self.continuityTimer invalidate];
        self.continuityTimer = nil;

        return taskId;
    }
}

- (void)removeTask:(OWSTaskId)taskId
{
    OWSAssertDebug(taskId);

    @synchronized(self)
    {
        OWSAssertDebug(self.expirationMap[taskId] != nil);

        [self.expirationMap removeObjectForKey:taskId];

        // This timer will ensure that we keep the background task active (if necessary)
        // for an extra fraction of a second to provide continuity between tasks.
        // This makes it easier and safer to use background tasks, since most code
        // should be able to ensure background tasks by "narrowly" wrapping
        // their core logic with a OWSBackgroundTask and not worrying about "hand off"
        // between OWSBackgroundTasks.
        [self.continuityTimer invalidate];
        self.continuityTimer = [NSTimer weakScheduledTimerWithTimeInterval:0.25f
                                                                    target:self
                                                                  selector:@selector(timerDidFire)
                                                                  userInfo:nil
                                                                   repeats:NO];

        [self ensureBackgroundTaskState];
    }
}

// Begins or end a background task if necessary.
- (BOOL)ensureBackgroundTaskState
{
    if (!CurrentAppContext().isMainApp) {
        // We can't create background tasks in the SAE, but pretend that we succeeded.
        return YES;
    }

    @synchronized(self)
    {
        // We only want to have a background task if we are:
        // a) "not active" AND
        // b1) there is one or more active instance of OWSBackgroundTask OR...
        // b2) ...there _was_ an active instance recently.
        BOOL shouldHaveBackgroundTask = (!self.isAppActive && (self.expirationMap.count > 0 || self.continuityTimer));
        BOOL hasBackgroundTask = self.backgroundTaskId != UIBackgroundTaskInvalid;

        if (shouldHaveBackgroundTask == hasBackgroundTask) {
            // Current state is correct.
            return YES;
        } else if (shouldHaveBackgroundTask) {
            OWSLogInfo(@"Starting background task.");
            return [self startBackgroundTask];
        } else {
            // Need to end background task.
            OWSLogInfo(@"Ending background task.");
            UIBackgroundTaskIdentifier backgroundTaskId = self.backgroundTaskId;
            self.backgroundTaskId = UIBackgroundTaskInvalid;
            [CurrentAppContext() endBackgroundTask:backgroundTaskId];
            return YES;
        }
    }
}

// Returns NO if the background task cannot be begun.
- (BOOL)startBackgroundTask
{
    OWSAssertDebug(CurrentAppContext().isMainApp);

    @synchronized(self)
    {
        OWSAssertDebug(self.backgroundTaskId == UIBackgroundTaskInvalid);

        self.backgroundTaskId = [CurrentAppContext() beginBackgroundTaskWithExpirationHandler:^{
            // Supposedly [UIApplication beginBackgroundTaskWithExpirationHandler]'s handler
            // will always be called on the main thread, but in practice we've observed
            // otherwise.
            //
            // See:
            // https://developer.apple.com/documentation/uikit/uiapplication/1623031-beginbackgroundtaskwithexpiratio)
            OWSAssertDebug([NSThread isMainThread]);

            [self backgroundTaskExpired];
        }];

        // If the background task could not begin, return NO to indicate that.
        if (self.backgroundTaskId == UIBackgroundTaskInvalid) {
            OWSLogError(@"background task could not be started.");

            return NO;
        }
        return YES;
    }
}

- (void)backgroundTaskExpired
{
    UIBackgroundTaskIdentifier backgroundTaskId;
    NSDictionary<OWSTaskId, BackgroundTaskExpirationBlock> *expirationMap;

    @synchronized(self)
    {
        backgroundTaskId = self.backgroundTaskId;
        self.backgroundTaskId = UIBackgroundTaskInvalid;

        expirationMap = [self.expirationMap copy];
        [self.expirationMap removeAllObjects];
    }

    // Supposedly [UIApplication beginBackgroundTaskWithExpirationHandler]'s handler
    // will always be called on the main thread, but in practice we've observed
    // otherwise.  OWSBackgroundTask's API guarantees that completionBlock will
    // always be called on the main thread, so we use DispatchSyncMainThreadSafe()
    // to ensure that.  We thereby ensure that we don't end the background task
    // until all of the completion blocks have completed.
    DispatchSyncMainThreadSafe(^{
        for (BackgroundTaskExpirationBlock expirationBlock in expirationMap.allValues) {
            expirationBlock();
        }
        if (backgroundTaskId != UIBackgroundTaskInvalid) {
            // Apparently we need to "end" even expired background tasks.
            [CurrentAppContext() endBackgroundTask:backgroundTaskId];
        }
    });
}

- (void)timerDidFire
{
    @synchronized(self)
    {
        [self.continuityTimer invalidate];
        self.continuityTimer = nil;

        [self ensureBackgroundTaskState];
    }
}

@end

#pragma mark -

@interface OWSBackgroundTask ()

@property (nonatomic, readonly) NSString *label;

// This property should only be accessed while synchronized on this instance.
@property (nonatomic, nullable) OWSTaskId taskId;

// This property should only be accessed while synchronized on this instance.
@property (nonatomic, nullable) BackgroundTaskCompletionBlock completionBlock;

@end

#pragma mark -

@implementation OWSBackgroundTask

+ (OWSBackgroundTask *)backgroundTaskWithLabelStr:(const char *)labelStr
{
    OWSAssertDebug(labelStr);

    NSString *label = [NSString stringWithFormat:@"%s", labelStr];
    return [[OWSBackgroundTask alloc] initWithLabel:label completionBlock:nil];
}

+ (OWSBackgroundTask *)backgroundTaskWithLabelStr:(const char *)labelStr
                                  completionBlock:(BackgroundTaskCompletionBlock)completionBlock
{

    OWSAssertDebug(labelStr);

    NSString *label = [NSString stringWithFormat:@"%s", labelStr];
    return [[OWSBackgroundTask alloc] initWithLabel:label completionBlock:completionBlock];
}

+ (OWSBackgroundTask *)backgroundTaskWithLabel:(NSString *)label
{
    return [[OWSBackgroundTask alloc] initWithLabel:label completionBlock:nil];
}

+ (OWSBackgroundTask *)backgroundTaskWithLabel:(NSString *)label
                               completionBlock:(BackgroundTaskCompletionBlock)completionBlock
{
    return [[OWSBackgroundTask alloc] initWithLabel:label completionBlock:completionBlock];
}

- (instancetype)initWithLabel:(NSString *)label completionBlock:(BackgroundTaskCompletionBlock _Nullable)completionBlock
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertDebug(label.length > 0);

    _label = label;
    self.completionBlock = completionBlock;

    [self startBackgroundTask];

    return self;
}

- (void)dealloc
{
    [self endBackgroundTask];
}

- (void)startBackgroundTask
{
    __weak typeof(self) weakSelf = self;
    self.taskId = [OWSBackgroundTaskManager.sharedManager addTaskWithExpirationBlock:^{
        DispatchMainThreadSafe(^{
            OWSBackgroundTask *strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            OWSLogVerbose(@"task expired");

            // Make a local copy of completionBlock to ensure that it is called
            // exactly once.
            BackgroundTaskCompletionBlock _Nullable completionBlock = nil;

            @synchronized(strongSelf)
            {
                if (!strongSelf.taskId) {
                    return;
                }
                OWSLogInfo(@"%@ background task expired.", strongSelf.label);
                strongSelf.taskId = nil;

                completionBlock = strongSelf.completionBlock;
                strongSelf.completionBlock = nil;
            }

            if (completionBlock) {
                completionBlock(BackgroundTaskState_Expired);
            }
        });
    }];

    // If a background task could not be begun, call the completion block.
    if (!self.taskId) {
        OWSLogError(@"%@ background task could not be started.", self.label);

        // Make a local copy of completionBlock to ensure that it is called
        // exactly once.
        BackgroundTaskCompletionBlock _Nullable completionBlock;
        @synchronized(self)
        {
            completionBlock = self.completionBlock;
            self.completionBlock = nil;
        }
        if (completionBlock) {
            DispatchMainThreadSafe(^{
                completionBlock(BackgroundTaskState_CouldNotStart);
            });
        }
    }
}

- (void)endBackgroundTask
{
    // Make a local copy of this state, since this method is called by `dealloc`.
    BackgroundTaskCompletionBlock _Nullable completionBlock;

    @synchronized(self)
    {
        if (!self.taskId) {
            return;
        }
        [OWSBackgroundTaskManager.sharedManager removeTask:self.taskId];
        self.taskId = nil;

        completionBlock = self.completionBlock;
        self.completionBlock = nil;
    }

    // endBackgroundTask must be called on the main thread.
    DispatchMainThreadSafe(^{
        if (completionBlock) {
            completionBlock(BackgroundTaskState_Success);
        }
    });
}

@end

NS_ASSUME_NONNULL_END
