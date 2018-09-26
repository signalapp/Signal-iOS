//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSGroupAvatarBuilder.h"
#import "OWSContactsManager.h"
#import "TSGroupThread.h"
#import "UIColor+OWS.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/SSKEnvironment.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSGroupAvatarBuilder ()

@property (nonatomic, readonly) TSGroupThread *thread;
@property (nonatomic, readonly) NSUInteger diameter;

@end

@implementation OWSGroupAvatarBuilder

- (instancetype)initWithThread:(TSGroupThread *)thread diameter:(NSUInteger)diameter
{
    self = [super init];
    if (!self) {
        return self;
    }

    _thread = thread;
    _diameter = diameter;

    return self;
}

- (nullable UIImage *)buildSavedImage
{
    return self.thread.groupModel.groupImage;
}

+ (OWSContactsManager *)contactsManager
{
    return (OWSContactsManager *)SSKEnvironment.shared.contactsManager;
}

- (nullable UIImage *)buildDefaultImage
{
    NSString *cacheKey = [NSString stringWithFormat:@"%@-%d", self.thread.uniqueId, Theme.isDarkThemeEnabled];

    UIImage *cachedAvatar =
        [OWSGroupAvatarBuilder.contactsManager.avatarCache imageForKey:cacheKey diameter:(CGFloat)self.diameter];
    if (cachedAvatar) {
        return cachedAvatar;
    }

    UIColor *backgroundColor =
        [UIColor ows_conversationColorForColorName:self.thread.conversationColorName isShaded:Theme.isDarkThemeEnabled];
    UIImage *_Nullable image =
        [OWSGroupAvatarBuilder groupAvatarImageWithBackgroundColor:backgroundColor diameter:self.diameter];
    if (!image) {
        return nil;
    }

    [OWSGroupAvatarBuilder.contactsManager.avatarCache setImage:image forKey:cacheKey diameter:self.diameter];
    return image;
}

+ (nullable UIImage *)defaultGroupAvatarImage
{
    NSUInteger diameter = 200;
    NSString *cacheKey = [NSString stringWithFormat:@"default-group-avatar-%d", Theme.isDarkThemeEnabled];

    UIImage *cachedAvatar = [self.contactsManager.avatarCache imageForKey:cacheKey diameter:(CGFloat)diameter];
    if (cachedAvatar) {
        return cachedAvatar;
    }

    // TODO: Verify with Myles.
    UIColor *backgroundColor = UIColor.ows_signalBlueColor;
    UIImage *_Nullable image = [self groupAvatarImageWithBackgroundColor:backgroundColor diameter:diameter];
    if (!image) {
        return nil;
    }

    [self.contactsManager.avatarCache setImage:image forKey:cacheKey diameter:diameter];
    return image;
}

+ (nullable UIImage *)groupAvatarImageWithBackgroundColor:(UIColor *)backgroundColor diameter:(NSUInteger)diameter
{
    UIImage *icon = [UIImage imageNamed:@"group-avatar"];
    CGSize iconSize = CGSizeScale(icon.size, diameter / kStandardAvatarSize);
    return
        [OWSAvatarBuilder avatarImageWithIcon:icon iconSize:iconSize backgroundColor:backgroundColor diameter:diameter];
}

@end

NS_ASSUME_NONNULL_END
