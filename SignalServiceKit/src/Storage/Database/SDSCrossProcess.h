//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// This class can be used by SDSDatabaseStorage to learn of
// database writes by other processes.
//
// * notifyChanged should be called after every write
//   transaction completes.
// * callback is invoked when a write from another process
//   is detected.
@interface SDSCrossProcess : NSObject

// This property should be set on the main thread.
// It will only be invoked on the main thread.
@property (nonatomic, nullable) dispatch_block_t callback;

- (void)notifyChangedAsync;

@end

NS_ASSUME_NONNULL_END
