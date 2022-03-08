//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/ProfileManagerProtocol.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@interface OWSFakeProfileManager : NSObject <ProfileManagerProtocol>
@property (nullable, nonatomic, copy) NSDictionary<SignalServiceAddress *, NSString *> *fakeDisplayNames;
@property (nullable, nonatomic, copy) NSDictionary<SignalServiceAddress *, NSString *> *fakeUsernames;

@property (nonatomic) NSMutableDictionary<SignalServiceAddress *, NSNumber *> *stubbedUuidCapabilitiesMap;

@end

#endif

NS_ASSUME_NONNULL_END
