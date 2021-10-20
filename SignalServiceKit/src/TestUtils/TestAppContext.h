//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/AppContext.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@interface TestAppContext : NSObject <AppContext>

@property (nonatomic, readonly, class) NSString *testDebugLogsDirPath;

@end

#endif

NS_ASSUME_NONNULL_END
