//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern const NSUInteger kSmallAvatarSize;
extern const NSUInteger kStandardAvatarSize;
extern const NSUInteger kMediumAvatarSize;
extern const NSUInteger kLargeAvatarSize;

typedef NS_CLOSED_ENUM(NSUInteger, LocalUserAvatarMode) {
    // We should use this value by default.
    LocalUserAvatarModeAsUser = 0,
    LocalUserAvatarModeNoteToSelf,
};

@class SDSAnyReadTransaction;
@class TSThread;
@class UIImage;

@interface OWSAvatarBuilder : NSObject

+ (nullable UIImage *)buildImageForThread:(TSThread *)thread
                                 diameter:(NSUInteger)diameter
                      localUserAvatarMode:(LocalUserAvatarMode)localUserAvatarMode
    NS_SWIFT_NAME(buildImage(thread:diameter:localUserAvatarMode:));

+ (nullable UIImage *)buildImageForThread:(TSThread *)thread
                                 diameter:(NSUInteger)diameter
                      localUserAvatarMode:(LocalUserAvatarMode)localUserAvatarMode
                              transaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(buildImage(thread:diameter:localUserAvatarMode:transaction:));

+ (nullable UIImage *)buildRandomAvatarWithDiameter:(NSUInteger)diameter;
+ (nullable UIImage *)buildNoiseAvatarWithDiameter:(NSUInteger)diameter;

- (nullable UIImage *)buildSavedImage;
- (nullable UIImage *)buildSavedImageWithTransaction:(SDSAnyReadTransaction *)transaction;
- (nullable UIImage *)buildDefaultImage;
- (nullable UIImage *)build;
- (nullable UIImage *)buildWithTransaction:(SDSAnyReadTransaction *)transaction;

+ (nullable UIImage *)avatarImageWithInitials:(NSString *)initials
                              backgroundColor:(UIColor *)backgroundColor
                                     diameter:(NSUInteger)diameter;

+ (nullable UIImage *)avatarImageWithIcon:(UIImage *)icon
                                 iconSize:(CGSize)iconSize
                          backgroundColor:(UIColor *)backgroundColor
                                 diameter:(NSUInteger)diameter;

+ (nullable UIImage *)avatarImageWithIcon:(UIImage *)icon
                                 iconSize:(CGSize)iconSize
                                iconColor:(UIColor *)iconColor
                          backgroundColor:(UIColor *)backgroundColor
                                 diameter:(NSUInteger)diameter;

+ (UIColor *)avatarForegroundColor;

@end

NS_ASSUME_NONNULL_END
