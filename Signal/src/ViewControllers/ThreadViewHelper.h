//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@protocol ThreadViewHelperDelegate <NSObject>

- (void)threadListDidChange;

@end

#pragma mark -

@class TSThread;

// A helper class
@interface ThreadViewHelper : NSObject

@property (nonatomic, weak) id<ThreadViewHelperDelegate> delegate;

@property (nonatomic, readonly) NSMutableArray<TSThread *> *threads;

@end
