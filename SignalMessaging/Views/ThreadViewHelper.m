//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ThreadViewHelper.h"
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/StorageCoordinator.h>
#import <SignalServiceKit/TSDatabaseView.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface ThreadViewHelper () <UIDatabaseSnapshotDelegate>

@property (nonatomic, nullable) YapDatabaseViewMappings *threadMappings;
@property (nonatomic) BOOL shouldObserveDBModifications;

@end

#pragma mark -

@implementation ThreadViewHelper

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

// POST GRDB TODO - Remove
- (nullable OWSPrimaryStorage *)primaryStorage
{
    return SSKEnvironment.shared.primaryStorage;
}

#pragma mark -

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    [self initializeMapping];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)initializeMapping
{
    OWSAssertIsOnMainThread();

    [self.databaseStorage appendUIDatabaseSnapshotDelegate:self];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:OWSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:OWSApplicationWillResignActiveNotification
                                               object:nil];

    [self updateShouldObserveDBModifications];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    [self updateShouldObserveDBModifications];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    [self updateShouldObserveDBModifications];
}

- (void)updateShouldObserveDBModifications
{
    self.shouldObserveDBModifications = CurrentAppContext().isAppForegroundAndActive;
}

// Don't observe database change notifications when the app is in the background.
//
// Instead, rebuild model state when app enters foreground.
- (void)setShouldObserveDBModifications:(BOOL)shouldObserveDBModifications
{
    if (_shouldObserveDBModifications == shouldObserveDBModifications) {
        return;
    }

    _shouldObserveDBModifications = shouldObserveDBModifications;

    if (shouldObserveDBModifications) {
        [self updateThreads];
    }
}

#pragma mark - Database

- (void)updateThreads
{
    OWSAssertIsOnMainThread();

    NSMutableArray<TSThread *> *threads = [NSMutableArray new];
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        AnyThreadFinder *threadFinder = [AnyThreadFinder new];
        NSError *_Nullable error;
        [threadFinder enumerateVisibleThreadsWithIsArchived:NO
                                                transaction:transaction
                                                      error:&error
                                                      block:^(TSThread *thread) {
                                                          [threads addObject:thread];
                                                      }];
        if (error != nil) {
            OWSFailDebug(@"error: %@", error);
        }
    }];
    _threads = [threads copy];
}

#pragma mark - UIDatabaseSnapshotDelegate

- (void)uiDatabaseSnapshotWillUpdate
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(AppReadiness.isAppReady);
}

- (void)uiDatabaseSnapshotDidUpdateWithDatabaseChanges:(id<UIDatabaseChanges>)databaseChanges
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(AppReadiness.isAppReady);

    if (![databaseChanges didUpdateModelWithCollection:TSThread.collection]) {
        return;
    }
    if (!self.shouldObserveDBModifications) {
        return;
    }

    [self updateThreads];
}

- (void)uiDatabaseSnapshotDidUpdateExternally
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(AppReadiness.isAppReady);

    if (!self.shouldObserveDBModifications) {
        return;
    }

    [self updateThreads];
}

- (void)uiDatabaseSnapshotDidReset
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(AppReadiness.isAppReady);

    if (!self.shouldObserveDBModifications) {
        return;
    }

    [self updateThreads];
}

@end

NS_ASSUME_NONNULL_END
