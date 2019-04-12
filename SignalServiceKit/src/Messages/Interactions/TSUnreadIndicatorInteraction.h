//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSInteraction.h>

NS_ASSUME_NONNULL_BEGIN

// This class is vestigial.
__attribute__((deprecated)) @interface TSUnreadIndicatorInteraction : TSInteraction

- (instancetype)initWithUniqueId:(NSString *)uniqueId
                        receivedAtTimestamp:(uint64_t)receivedAtTimestamp
                                     sortId:(uint64_t)sortId
                                  timestamp:(uint64_t)timestamp
                             uniqueThreadId:(NSString *)uniqueThreadId
NS_SWIFT_NAME(init(uniqueId:receivedAtTimestamp:sortId:timestamp:uniqueThreadId:));

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
