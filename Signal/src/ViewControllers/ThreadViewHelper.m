//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ThreadViewHelper.h"
#import <SignalServiceKit/TSDatabaseView.h>
#import <SignalServiceKit/TSStorageManager.h>
#import <SignalServiceKit/TSThread.h>
#import <YapDatabase/YapDatabaseConnection.h>
#import <YapDatabase/YapDatabaseViewChange.h>
#import <YapDatabase/YapDatabaseViewConnection.h>

NS_ASSUME_NONNULL_BEGIN

@interface ThreadViewHelper ()

@property (nonatomic) YapDatabaseConnection *uiDatabaseConnection;
@property (nonatomic) YapDatabaseViewMappings *threadMappings;

@end

@implementation ThreadViewHelper

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
    OWSAssert([NSThread isMainThread]);

    NSString *grouping = TSInboxGroup;

    self.threadMappings =
        [[YapDatabaseViewMappings alloc] initWithGroups:@[ grouping ] view:TSThreadDatabaseViewExtensionName];
    [self.threadMappings setIsReversed:YES forGroup:grouping];

    __weak ThreadViewHelper *weakSelf = self;
    [self.uiDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.threadMappings updateWithTransaction:transaction];

        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf updateThreads];
            [weakSelf.delegate threadListDidChange];
        });
    }];
}

#pragma mark - Database

- (YapDatabaseConnection *)uiDatabaseConnection
{
    NSAssert([NSThread isMainThread], @"Must access uiDatabaseConnection on main thread!");
    if (!_uiDatabaseConnection) {
        YapDatabase *database = TSStorageManager.sharedManager.database;
        _uiDatabaseConnection = [database newConnection];
        [_uiDatabaseConnection beginLongLivedReadTransaction];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(yapDatabaseModified:)
                                                     name:YapDatabaseModifiedNotification
                                                   object:database];
    }
    return _uiDatabaseConnection;
}

- (void)yapDatabaseModified:(NSNotification *)notification
{
    OWSAssert([NSThread isMainThread]);

    NSArray *notifications = [self.uiDatabaseConnection beginLongLivedReadTransaction];
    NSArray *sectionChanges = nil;
    NSArray *rowChanges = nil;
    [[self.uiDatabaseConnection ext:TSThreadDatabaseViewExtensionName] getSectionChanges:&sectionChanges
                                                                              rowChanges:&rowChanges
                                                                        forNotifications:notifications
                                                                            withMappings:self.threadMappings];
    if (sectionChanges.count == 0 && rowChanges.count == 0) {
        // Ignore irrelevant modifications.
        return;
    }

    [self updateThreads];

    [self.delegate threadListDidChange];
}

- (void)updateThreads
{
    OWSAssert([NSThread isMainThread]);

    NSMutableArray<TSThread *> *threads = [NSMutableArray new];
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        NSUInteger numberOfSections = [self.threadMappings numberOfSections];
        OWSAssert(numberOfSections == 1);
        for (NSUInteger section = 0; section < numberOfSections; section++) {
            NSUInteger numberOfItems = [self.threadMappings numberOfItemsInSection:section];
            for (NSUInteger item = 0; item < numberOfItems; item++) {
                TSThread *thread = [[transaction extension:TSThreadDatabaseViewExtensionName]
                    objectAtIndexPath:[NSIndexPath indexPathForItem:(NSInteger)item inSection:(NSInteger)section]
                         withMappings:self.threadMappings];
                [threads addObject:thread];
            }
        }
    }];

    _threads = [threads copy];
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
