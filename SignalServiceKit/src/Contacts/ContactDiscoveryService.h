//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface ContactDiscoveryService : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedService;

- (void)testService;

@end

NS_ASSUME_NONNULL_END
