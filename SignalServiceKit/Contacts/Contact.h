//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Contact : NSObject <NSSecureCoding>

@property (nonatomic, readonly, nullable) NSString *cnContactId;
@property (nullable, readonly, nonatomic) NSString *firstName;
@property (nullable, readonly, nonatomic) NSString *lastName;
@property (nullable, readonly, nonatomic) NSString *nickname;
@property (readonly, nonatomic) NSString *fullName;

@property (nonatomic, readonly) BOOL isFromLocalAddressBook;

- (instancetype)initWithCNContactId:(nullable NSString *)cnContactId
                          firstName:(nullable NSString *)firstName
                           lastName:(nullable NSString *)lastName
                           nickname:(nullable NSString *)nickname
                           fullName:(NSString *)fullName NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
