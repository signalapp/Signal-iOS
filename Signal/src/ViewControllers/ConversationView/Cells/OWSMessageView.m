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

- (OWSMessageGestureLocation)gestureLocationForLocation:(CGPoint)locationInMessageBubble
{
    OWSAbstractMethod();

    return OWSMessageGestureLocation_Default;
}

- (void)handleTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAbstractMethod();
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

@end

NS_ASSUME_NONNULL_END
