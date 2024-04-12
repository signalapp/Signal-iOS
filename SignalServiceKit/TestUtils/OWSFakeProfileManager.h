//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/ProfileManagerProtocol.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@class OWSUserProfile;

@interface OWSFakeProfileManager : NSObject <ProfileManagerProtocol>
@property (nullable, nonatomic, copy) NSDictionary<SignalServiceAddress *, OWSUserProfile *> *fakeUserProfiles;

@property (nonatomic) NSMutableDictionary<SignalServiceAddress *, OWSAES256Key *> *profileKeys;

@property (nonatomic) NSMutableDictionary<SignalServiceAddress *, NSNumber *> *stubbedStoriesCapabilitiesMap;

@end

#endif

NS_ASSUME_NONNULL_END
