//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageSender.h"
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSFakeMessageSender : OWSMessageSender

- (instancetype)init;
- (instancetype)initWithExpectation:(XCTestExpectation *)expectation;

@property (nonatomic, readonly) XCTestExpectation *expectation;

@end

NS_ASSUME_NONNULL_END
