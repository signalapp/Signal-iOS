//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "Threading.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <pthread.h>

NS_ASSUME_NONNULL_BEGIN

void DispatchMainThreadSafeObjc(dispatch_block_t block)
{
    OWSCAssertDebug(block);

    [ThreadingObjcBridge dispatchMainThreadSafe:block];
}

BOOL DispatchQueueIsCurrentQueue(dispatch_queue_t testQueue)
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    void *currentQueuePtr = (__bridge void *)dispatch_get_current_queue();
#pragma clang diagnostic pop
    return (currentQueuePtr == (__bridge void *)testQueue);
}

double _CurrentStackUsage(void)
{
#if TARGET_CPU_X86 || TARGET_CPU_X86_64 || TARGET_CPU_ARM || TARGET_CPU_ARM64
    pthread_t _Nullable currentThread = pthread_self();
    if (!currentThread) {
        OWSCFailDebug(@"No current thread");
        return NAN;
    }

    size_t stackSize = pthread_get_stacksize_np(currentThread);
    void *baseAddr = pthread_get_stackaddr_np(currentThread);

    // In all of our supported platforms, the stack grows towards down towards 0.
    // The local var address should always be less than our stack base.
    ptrdiff_t usedBytes = baseAddr - ((void *)&baseAddr);

    if (stackSize > 0 && baseAddr > 0 && usedBytes > 0 && (size_t)usedBytes < stackSize) {
        double result = ((double)usedBytes / (double)stackSize);
        return MAX(0.0, MIN(result, 1.0));
    } else {
        OWSCFailDebug(@"Unexpected stack format");
        return NAN;
    }
#else /* !x86(_64) && !arm(64) */
#error Double check this implementation to ensure it works for the platform
    return NAN;
#endif
}

NS_ASSUME_NONNULL_END
