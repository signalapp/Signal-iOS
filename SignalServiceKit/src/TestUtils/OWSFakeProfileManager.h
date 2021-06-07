//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/ProfileManagerProtocol.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@interface OWSFakeProfileManager : NSObject <ProfileManagerProtocol>

@property (nonatomic) NSMutableDictionary<SignalServiceAddress *, NSNumber *> *stubbedUuidCapabilitiesMap;

@end

#endif

NS_ASSUME_NONNULL_END
