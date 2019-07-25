//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSSyncManagerProtocol.h>

NS_ASSUME_NONNULL_BEGIN

@class AnyPromise;
@class OWSContactsManager;
@class OWSIdentityManager;
@class OWSMessageSender;
@class OWSProfileManager;
@class SDSKeyValueStore;

@interface OWSSyncManager : NSObject <OWSSyncManagerProtocol>

+ (SDSKeyValueStore *)keyValueStore;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initDefault NS_DESIGNATED_INITIALIZER;

+ (instancetype)shared;

@end

NS_ASSUME_NONNULL_END
