//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSInteraction.h>

NS_ASSUME_NONNULL_BEGIN

// This class is vestigial.
__attribute__((deprecated)) @interface TSUnreadIndicatorInteraction : TSInteraction

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
