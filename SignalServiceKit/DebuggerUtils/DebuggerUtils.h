//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

#ifdef DEBUG

NS_ASSUME_NONNULL_BEGIN

// Returns whether the debugger is attached to this process.
BOOL IsDebuggerAttached(void);

// If the debugger is attached, break (like a breakpoint). Otherwise, abort.
void TrapDebugger(void);

NS_ASSUME_NONNULL_END

#else // DEBUG

NS_INLINE BOOL IsDebuggerAttached(void)
{
    return NO;
}

NS_INLINE void TrapDebugger(void)
{
}

#endif // DEBUG
