//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

// This class can be safely accessed and used from any thread.
@interface OWSProfilesManager : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

@end

NS_ASSUME_NONNULL_END
