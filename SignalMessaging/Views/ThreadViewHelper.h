//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@protocol ThreadViewHelperDelegate <NSObject>

- (void)threadListDidChange;

@end

#pragma mark -

@class TSThread;

// A helper class for views that want to present the list of threads
// that show up in home view, and in the same order.
//
// It observes changes to the threads & their ordering and informs
// its delegate when they happen.
@interface ThreadViewHelper : NSObject

@property (nonatomic, weak) id<ThreadViewHelperDelegate> delegate;

@property (nonatomic, readonly) NSMutableArray<TSThread *> *threads;

@end

NS_ASSUME_NONNULL_END
