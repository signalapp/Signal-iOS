//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern const NSUInteger kStandardAvatarSize;
extern const NSUInteger kLargeAvatarSize;

@class TSThread;
@class UIImage;

@interface OWSAvatarBuilder : NSObject

+ (nullable UIImage *)buildImageForThread:(TSThread *)thread
                                 diameter:(NSUInteger)diameter NS_SWIFT_NAME(buildImage(thread:diameter:));

+ (nullable UIImage *)buildRandomAvatarWithDiameter:(NSUInteger)diameter;

- (nullable UIImage *)buildSavedImage;
- (nullable UIImage *)buildDefaultImage;
- (nullable UIImage *)build;

+ (nullable UIImage *)avatarImageWithInitials:(NSString *)initials
                              backgroundColor:(UIColor *)backgroundColor
                                     diameter:(NSUInteger)diameter;

+ (nullable UIImage *)avatarImageWithIcon:(UIImage *)icon
                                 iconSize:(CGSize)iconSize
                          backgroundColor:(UIColor *)backgroundColor
                                 diameter:(NSUInteger)diameter;

@end

NS_ASSUME_NONNULL_END
