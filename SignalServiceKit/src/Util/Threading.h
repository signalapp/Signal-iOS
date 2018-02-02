//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef void (^SimpleBlock)(void);

// The block is executed immediately if called from the
// main thread; otherwise it is dispatched async to the
// main thread.
void DispatchMainThreadSafe(SimpleBlock block);

// The block is executed immediately if called from the
// main thread; otherwise it is dispatched sync to the
// main thread.
void DispatchSyncMainThreadSafe(SimpleBlock block);

NS_ASSUME_NONNULL_END
