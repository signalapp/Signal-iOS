// Created by Michael Kirk on 12/20/16.
// Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class TSStorageManager;

@interface OWSCensorshipConfiguration : NSObject

- (NSString *)frontingHost:(NSString *)e164PhonNumber;
- (NSString *)reflectorHost;
- (BOOL)isCensoredPhoneNumber:(NSString *)e164PhonNumber;

@end

NS_ASSUME_NONNULL_END
