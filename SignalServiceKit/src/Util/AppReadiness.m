//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AppReadiness.h"
#import "Threading.h"

NS_ASSUME_NONNULL_BEGIN

@interface AppReadiness ()

@property (atomic) BOOL isAppReady;

@property (nonatomic) NSMutableArray<AppReadyBlock> *appReadyBlocks;

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

    self.appReadyBlocks = [NSMutableArray new];

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
    OWSAssertDebug(block);

    if (self.isAppReady) {
        block();
        return;
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
    OWSAssertDebug(!self.isAppReady);

    OWSLogInfo(@"");

    self.isAppReady = YES;

    [self runAppReadyBlocks];
}

- (void)runAppReadyBlocks
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.isAppReady);

    NSArray<AppReadyBlock> *appReadyBlocks = [self.appReadyBlocks copy];
    [self.appReadyBlocks removeAllObjects];
    for (AppReadyBlock block in appReadyBlocks) {
        block();
    }
}

@end

NS_ASSUME_NONNULL_END
