//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageView.h"
#import "Signal-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSMessageView

- (void)configureViews
{
    OWSAbstractMethod();
}

- (void)loadContent
{
    OWSAbstractMethod();
}

- (void)unloadContent
{
    OWSAbstractMethod();
}

- (void)prepareForReuse
{
    OWSAbstractMethod();
}

- (CGSize)measureSize
{
    OWSAbstractMethod();

    return CGSizeZero;
}

+ (UIFont *)senderNameFont
{
    return UIFont.ows_dynamicTypeSubheadlineFont.ows_mediumWeight;
}

+ (NSDictionary *)senderNamePrimaryAttributes
{
    return @{
        NSFontAttributeName : self.senderNameFont,
        NSForegroundColorAttributeName : ConversationStyle.bubbleTextColorIncoming,
    };
}

+ (NSDictionary *)senderNameSecondaryAttributes
{
    return @{
        NSFontAttributeName : self.senderNameFont.ows_italic,
        NSForegroundColorAttributeName : ConversationStyle.bubbleTextColorIncoming,
    };
}

+ (NSString *)accessibilityLabelWithDescription:(NSString *)descriptionParam authorName:(nullable NSString *)authorName
{
    NSString *description = (descriptionParam.length > 0
            ? descriptionParam
            : NSLocalizedString(@"ACCESSIBILITY_LABEL_MESSAGE", @"Accessibility label for message."));
    if (authorName.length > 0) {
        return [@[ authorName, description ] componentsJoinedByString:@" "];
    } else {
        OWSFailDebug(@"Missing sender name.");
        return description;
    }
}

#pragma mark - Gestures

- (OWSMessageGestureLocation)gestureLocationForLocation:(CGPoint)locationInMessageBubble
{
    OWSAbstractMethod();

    return OWSMessageGestureLocation_Default;
}

- (void)addGestureHandlers
{
    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
    [self addGestureRecognizer:tap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(handlePanGesture:)];
    [self addGestureRecognizer:pan];
    [tap requireGestureRecognizerToFail:pan];
}

- (BOOL)willHandleTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAbstractMethod();
    return NO;
}

- (void)handleTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAbstractMethod();
}

- (BOOL)handlePanGesture:(UIPanGestureRecognizer *)sender
{
    OWSAbstractMethod();
    return NO;
}

@end

NS_ASSUME_NONNULL_END
