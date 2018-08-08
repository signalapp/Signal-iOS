//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSAvatarBuilder.h"
#import "JSQMessagesAvatarImageFactory.h"
#import "OWSContactAvatarBuilder.h"
#import "OWSGroupAvatarBuilder.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "UIColor+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSAvatarBuilder

+ (UIImage *)buildImageForThread:(TSThread *)thread
                        diameter:(NSUInteger)diameter
                 contactsManager:(OWSContactsManager *)contactsManager
{
    OWSAssert(thread);
    OWSAssert(contactsManager);

    OWSAvatarBuilder *avatarBuilder;
    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        NSString *colorName = thread.conversationColorName;
        UIColor *color = [UIColor ows_conversationColorForColorName:colorName];
        avatarBuilder = [[OWSContactAvatarBuilder alloc] initWithSignalId:contactThread.contactIdentifier
                                                                    color:color
                                                                 diameter:diameter
                                                          contactsManager:contactsManager];
    } else if ([thread isKindOfClass:[TSGroupThread class]]) {
        avatarBuilder = [[OWSGroupAvatarBuilder alloc] initWithThread:(TSGroupThread *)thread];
    } else {
        DDLogError(@"%@ called with unsupported thread: %@", self.logTag, thread);
    }
    return [avatarBuilder build];
}

+ (UIImage *)buildRandomAvatarWithDiameter:(NSUInteger)diameter
{
    NSArray<NSString *> *eyes = @[ @":", @"=", @"8", @"B" ];
    NSArray<NSString *> *mouths = @[ @"3", @")", @"(", @"|", @"\\", @"P", @"D", @"o" ];
    // eyebrows are rare
    NSArray<NSString *> *eyebrows = @[ @">", @"", @"", @"", @"" ];

    NSString *randomEye = eyes[arc4random_uniform((uint32_t)eyes.count)];
    NSString *randomMouth = mouths[arc4random_uniform((uint32_t)mouths.count)];
    NSString *randomEyebrow = eyebrows[arc4random_uniform((uint32_t)eyebrows.count)];
    NSString *face = [NSString stringWithFormat:@"%@%@%@", randomEyebrow, randomEye, randomMouth];

    CGFloat fontSize = (CGFloat)(diameter / 2.4);

    UIImage *srcImage =
        [[JSQMessagesAvatarImageFactory avatarImageWithUserInitials:face
                                                    backgroundColor:[UIColor colorWithRGBHex:0xaca6633]
                                                          textColor:[UIColor whiteColor]
                                                               font:[UIFont boldSystemFontOfSize:fontSize]
                                                           diameter:diameter] avatarImage];

    UIGraphicsBeginImageContext(srcImage.size);

    CGContextRef context = UIGraphicsGetCurrentContext();

    CGFloat width = srcImage.size.width;

    // Rotate
    CGContextTranslateCTM(context, width / 2, width / 2);
    CGContextRotateCTM(context, (CGFloat)M_PI_2);
    CGContextTranslateCTM(context, -width / 2, -width / 2);

    [srcImage drawAtPoint:CGPointMake(0, 0)];

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (UIImage *)build
{
    UIImage *_Nullable savedImage = [self buildSavedImage];
    if (savedImage) {
        return savedImage;
    } else {
        return [self buildDefaultImage];
    }
}

- (nullable UIImage *)buildSavedImage
{
    OWSAbstractMethod();
    return nil;
}

- (UIImage *)buildDefaultImage
{
    OWSAbstractMethod();
    return [UIImage new];
}

@end

NS_ASSUME_NONNULL_END
