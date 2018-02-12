//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSPrimaryStorage;

@interface OWSCensorshipConfiguration : NSObject

- (NSString *)frontingHost:(NSString *)e164PhoneNumber;
- (NSString *)signalServiceReflectorHost;
- (NSString *)CDNReflectorHost;
- (BOOL)isCensoredPhoneNumber:(NSString *)e164PhoneNumber;

@end

NS_ASSUME_NONNULL_END
