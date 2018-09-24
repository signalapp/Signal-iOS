//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSContactsManager;
@class TSThread;
@class UIImage;

@interface OWSAvatarBuilder : NSObject

+ (nullable UIImage *)buildImageForThread:(TSThread *)thread
                                 diameter:(NSUInteger)diameter
                          contactsManager:(OWSContactsManager *)contactsManager
    NS_SWIFT_NAME(buildImage(thread:diameter:contactsManager:));

+ (nullable UIImage *)buildRandomAvatarWithDiameter:(NSUInteger)diameter;

- (nullable UIImage *)buildSavedImage;
- (nullable UIImage *)buildDefaultImage;
- (nullable UIImage *)build;

+ (nullable UIImage *)avatarImageWithInitials:(NSString *)initials
                              backgroundColor:(UIColor *)backgroundColor
                                     diameter:(NSUInteger)diameter;

+ (nullable UIImage *)avatarImageWithIcon:(UIImage *)icon
                          backgroundColor:(UIColor *)backgroundColor
                                 diameter:(NSUInteger)diameter;

@end

NS_ASSUME_NONNULL_END
