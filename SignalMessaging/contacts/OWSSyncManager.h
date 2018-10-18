//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSSyncManagerProtocol.h>

NS_ASSUME_NONNULL_BEGIN

@class AnyPromise;
@class OWSContactsManager;
@class OWSIdentityManager;
@class OWSMessageSender;
@class OWSProfileManager;

@interface OWSSyncManager : NSObject <OWSSyncManagerProtocol>

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initDefault NS_DESIGNATED_INITIALIZER;

+ (instancetype)shared;

@end

NS_ASSUME_NONNULL_END
