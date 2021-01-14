//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern const NSUInteger kSmallAvatarSize;
extern const NSUInteger kStandardAvatarSize;
extern const NSUInteger kMediumAvatarSize;
extern const NSUInteger kLargeAvatarSize;

@class SDSAnyReadTransaction;
@class TSThread;
@class UIImage;

@interface OWSAvatarBuilder : NSObject

+ (nullable UIImage *)buildImageForThread:(TSThread *)thread
                                 diameter:(NSUInteger)diameter NS_SWIFT_NAME(buildImage(thread:diameter:));

+ (nullable UIImage *)buildImageForThread:(TSThread *)thread
                                 diameter:(NSUInteger)diameter
                              transaction:(SDSAnyReadTransaction *)transaction NS_SWIFT_NAME(buildImage(thread:diameter:transaction:));

+ (nullable UIImage *)buildRandomAvatarWithDiameter:(NSUInteger)diameter;

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
