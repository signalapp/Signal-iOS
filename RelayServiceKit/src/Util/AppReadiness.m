//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AppReadiness.h"
#import "Threading.h"

NS_ASSUME_NONNULL_BEGIN

@interface AppReadiness ()

@property (atomic) BOOL isAppReady;

@property (nonatomic, nullable) NSMutableArray<AppReadyBlock> *appReadyBlocks;

@end

#pragma mark -

@implementation AppReadiness

+ (instancetype)sharedManager
{
    static AppReadiness *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
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

+ (BOOL)isAppReady
{
    return [self.sharedManager isAppReady];
}

+ (void)runNowOrWhenAppIsReady:(AppReadyBlock)block
{
    DispatchMainThreadSafe(^{
        [self.sharedManager runNowOrWhenAppIsReady:block];
    });
}

- (void)runNowOrWhenAppIsReady:(AppReadyBlock)block
{
    OWSAssertIsOnMainThread();
    OWSAssert(block);

    if (self.isAppReady) {
        block();
        return;
    }

    if (!self.appReadyBlocks) {
        self.appReadyBlocks = [NSMutableArray new];
    }
    [self.appReadyBlocks addObject:block];
}

+ (void)setAppIsReady
{
    [self.sharedManager setAppIsReady];
}

- (void)setAppIsReady
{
    OWSAssertIsOnMainThread();
    OWSAssert(!self.isAppReady);

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    self.isAppReady = YES;

    [self runAppReadyBlocks];
}

- (void)runAppReadyBlocks
{
    OWSAssertIsOnMainThread();
    OWSAssert(self.isAppReady);

    for (AppReadyBlock block in self.appReadyBlocks) {
        block();
    }
    self.appReadyBlocks = nil;
}

@end

NS_ASSUME_NONNULL_END
