//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef void (^SimpleBlock)();

// The block is executed immediately if called from the
// main thread; otherwise it is disptached async to the
// main thread.
void DispatchMainThreadSafe(SimpleBlock block);

NS_ASSUME_NONNULL_END
