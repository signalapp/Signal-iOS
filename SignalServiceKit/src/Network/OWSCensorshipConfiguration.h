//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSStorageManager;

@interface OWSCensorshipConfiguration : NSObject

- (NSString *)frontingHost:(NSString *)e164PhoneNumber;
- (NSString *)reflectorHost;
- (BOOL)isCensoredPhoneNumber:(NSString *)e164PhoneNumber;

@end

NS_ASSUME_NONNULL_END
