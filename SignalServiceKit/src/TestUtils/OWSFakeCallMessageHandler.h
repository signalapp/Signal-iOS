//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSCallMessageHandler.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@interface OWSFakeCallMessageHandler : NSObject <OWSCallMessageHandler>

@end

#endif

NS_ASSUME_NONNULL_END
