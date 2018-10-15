//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSContactsManager;
@class OWSIdentityManager;
@class OWSMessageSender;
@class OWSProfileManager;

@interface OWSContactsSyncing : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initDefault NS_DESIGNATED_INITIALIZER;

+ (instancetype)sharedManager;

@end

NS_ASSUME_NONNULL_END
