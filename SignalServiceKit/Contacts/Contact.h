//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Contact : NSObject <NSSecureCoding>

@property (nonatomic, readonly, nullable) NSString *cnContactId;
@property (nonatomic, readonly) NSString *firstName;
@property (nonatomic, readonly) NSString *lastName;
@property (nonatomic, readonly) NSString *nickname;
@property (nonatomic, readonly) NSString *fullName;

@property (nonatomic, readonly) BOOL isFromLocalAddressBook;

- (instancetype)initWithCNContactId:(nullable NSString *)cnContactId
                          firstName:(NSString *)firstName
                           lastName:(NSString *)lastName
                           nickname:(NSString *)nickname
                           fullName:(NSString *)fullName NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
