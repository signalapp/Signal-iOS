//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSThread;
@class OWSContactsManager;
@class UIImage;

@interface OWSAvatarBuilder : NSObject

+ (UIImage *)buildImageForThread:(TSThread *)thread
                        diameter:(NSUInteger)diameter
                 contactsManager:(OWSContactsManager *)contactsManager NS_SWIFT_NAME(buildImage(thread:diameter:contactsManager:));

+ (UIImage *)buildRandomAvatarWithDiameter:(NSUInteger)diameter;

- (nullable UIImage *)buildSavedImage;
- (UIImage *)buildDefaultImage;
- (UIImage *)build;

@end

NS_ASSUME_NONNULL_END
