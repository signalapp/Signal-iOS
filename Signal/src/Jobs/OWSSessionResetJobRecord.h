//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/SSKJobRecord.h>

@class TSContactThread;

NS_ASSUME_NONNULL_BEGIN

@interface OWSSessionResetJobRecord : SSKJobRecord

@property (nonatomic, readonly) NSString *contactThreadId;

- (instancetype)initWithContactThread:(TSContactThread *)contactThread
                                label:(NSString *)label NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (nullable)initWithLabel:(NSString *)label NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
