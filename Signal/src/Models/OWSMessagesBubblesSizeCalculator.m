//  Copyright (c) 2016 Open Whisper Systems. All rights reserved.

#import "OWSMessagesBubblesSizeCalculator.h"
#import "OWSCall.h"
#import "OWSDisplayedMessageCollectionViewCell.h"
#import "TSMessageAdapter.h"
#import "UIFont+OWS.h"
#import "tgmath.h" // generic math allows fmax to handle CGFLoat correctly on 32 & 64bit.
#import <JSQMessagesViewController/JSQMessagesCollectionViewFlowLayout.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * We use some private method to size our info messages.
 */
@interface OWSMessagesBubblesSizeCalculator (JSQPrivateMethods)

@property (strong, nonatomic, readonly) NSCache *cache;
@property (assign, nonatomic, readonly) NSUInteger minimumBubbleWidth;
@property (assign, nonatomic, readonly) BOOL usesFixedWidthBubbles;
@property (assign, nonatomic, readonly) NSInteger additionalInset;
@property (assign, nonatomic) CGFloat layoutWidthForFixedWidthBubbles;

- (CGSize)jsq_avatarSizeForMessageData:(id<JSQMessageData>)messageData
                            withLayout:(JSQMessagesCollectionViewFlowLayout *)layout;
- (CGFloat)textBubbleWidthForLayout:(JSQMessagesCollectionViewFlowLayout *)layout;
@end

@implementation OWSMessagesBubblesSizeCalculator

/**
 *  Computes and returns the size of the `messageBubbleImageView` property
 *  of a `JSQMessagesCollectionViewCell` for the specified messageData at indexPath.
 *
 *  @param messageData A message data object.
 *  @param indexPath   The index path at which messageData is located.
 *  @param layout      The layout object asking for this information.
 *
 *  @return A sizes that specifies the required dimensions to display the entire message contents.
 *  Note, this is *not* the entire cell, but only its message bubble.
 */
- (CGSize)messageBubbleSizeForMessageData:(id<JSQMessageData>)messageData
                              atIndexPath:(NSIndexPath *)indexPath
                               withLayout:(JSQMessagesCollectionViewFlowLayout *)layout
{
    if ([messageData isKindOfClass:[TSMessageAdapter class]]) {
        TSMessageAdapter *message = (TSMessageAdapter *)messageData;
        if (message.messageType == TSInfoMessageAdapter || message.messageType == TSErrorMessageAdapter) {
            return [self messageBubbleSizeForInfoMessageData:messageData atIndexPath:indexPath withLayout:layout];
        }
    }

    if ([messageData isKindOfClass:[OWSCall class]]) {
        return [self messageBubbleSizeForCallData:messageData atIndexPath:indexPath withLayout:layout];
    }

    CGSize size;
    // BEGIN HACK iOS10EmojiBug see: https://github.com/WhisperSystems/Signal-iOS/issues/1368
    if ([self shouldApplyiOS10EmojiFixToString:messageData.text font:layout.messageBubbleFont]) {
        size = [self withiOS10EmojiFixSuperMessageBubbleSizeForMessageData:messageData
                                                               atIndexPath:indexPath
                                                                withLayout:layout];
    } else {
        size = [super messageBubbleSizeForMessageData:messageData atIndexPath:indexPath withLayout:layout];
    }
    // END HACK iOS10EmojiBug see: https://github.com/WhisperSystems/Signal-iOS/issues/1368

    return CGSizeMake(size.width, size.height);
}

/**
 * Emoji sizing bug only affects iOS10. Unfortunately the "fix" for emoji font breaks some other fonts, so it's
 * important
 * to only apply it when emoji is actually present.
 */
- (BOOL)shouldApplyiOS10EmojiFixToString:(NSString *)string font:(UIFont *)font
{
    if (!string) {
        return NO;
    }

    BOOL isIOS10OrGreater =
        [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){.majorVersion = 10 }];
    if (!isIOS10OrGreater) {
        return NO;
    }

    __block BOOL foundEmoji = NO;
    NSDictionary *attributes = @{ NSFontAttributeName : font };

    NSMutableAttributedString *attributedString =
        [[NSMutableAttributedString alloc] initWithString:string attributes:attributes];
    [attributedString fixAttributesInRange:NSMakeRange(0, string.length)];
    [attributedString enumerateAttribute:NSFontAttributeName
                                 inRange:NSMakeRange(0, string.length)
                                 options:0
                              usingBlock:^(id _Nullable value, NSRange range, BOOL *_Nonnull stop) {
                                  UIFont *rangeFont = (UIFont *)value;
                                  if ([rangeFont.fontName isEqualToString:@".AppleColorEmojiUI"]) {
                                      DDLogVerbose(@"Detected Emoji at location: %lu, for length: %lu",
                                          (unsigned long)range.location,
                                          (unsigned long)range.length);
                                      foundEmoji = YES;
                                      *stop = YES;
                                  }
                              }];

    return foundEmoji;
}

/**
 * HACK iOS10EmojiBug see: https://github.com/WhisperSystems/Signal-iOS/issues/1368
 * As of iOS10.0 the UIEmoji font doesn't present proper line heights. In some cases this causes the last line in a
 * message to get cropped off.
 */
- (CGSize)withiOS10EmojiFixSuperMessageBubbleSizeForMessageData:(id<JSQMessageData>)messageData
                                                    atIndexPath:(NSIndexPath *)indexPath
                                                     withLayout:(JSQMessagesCollectionViewFlowLayout *)layout
{
    UIFont *emojiFont = [UIFont fontWithName:@".AppleColorEmojiUI" size:layout.messageBubbleFont.pointSize];
    CGSize superSize = [super messageBubbleSizeForMessageData:messageData atIndexPath:indexPath withLayout:layout];
    int lines = (int)floor(superSize.height / emojiFont.lineHeight);

    // Add an extra pixel per line to fit the emoji.
    return CGSizeMake(superSize.width, superSize.height + lines);
}


- (CGSize)messageBubbleSizeForInfoMessageData:(id<JSQMessageData>)messageData
                                  atIndexPath:(NSIndexPath *)indexPath
                                   withLayout:(JSQMessagesCollectionViewFlowLayout *)layout
{
    NSValue *cachedSize = [self.cache objectForKey:@([messageData messageHash])];
    if (cachedSize != nil) {
        return [cachedSize CGSizeValue];
    }

    CGSize finalSize = CGSizeZero;

    if ([messageData isMediaMessage]) {
        finalSize = [[messageData media] mediaViewDisplaySize];
    } else {
        ///////////////////
        // BEGIN InfoMessage sizing HACK
        // Braindead, and painstakingly produced.
        // If you want to change, check for clipping / excess space on 1, 2, and 3 line messages with short and long
        // words very near the edge.

//      CGSize avatarSize = [self jsq_avatarSizeForMessageData:messageData withLayout:layout];
//      //  from the cell xibs, there is a 2 point space between avatar and bubble
//      CGFloat spacingBetweenAvatarAndBubble = 2.0f;
//      CGFloat horizontalContainerInsets = layout.messageBubbleTextViewTextContainerInsets.left + layout.messageBubbleTextViewTextContainerInsets.right;
//      CGFloat horizontalFrameInsets = layout.messageBubbleTextViewFrameInsets.left + layout.messageBubbleTextViewFrameInsets.right;
//      CGFloat horizontalInsetsTotal = horizontalContainerInsets + horizontalFrameInsets + spacingBetweenAvatarAndBubble;
//      CGFloat maximumTextWidth = [self textBubbleWidthForLayout:layout] - avatarSize.width - layout.messageBubbleLeftRightMargin - horizontalInsetsTotal;

        // The full layout width, less the textView margins from xib.
//        CGFloat horizontalInsetsTotal = 12.0; cropped 3rd line
        CGFloat horizontalInsetsTotal = 50.0;
        CGFloat maximumTextWidth = [self textBubbleWidthForLayout:layout] - horizontalInsetsTotal;

        CGRect stringRect = [[messageData text]
            boundingRectWithSize:CGSizeMake(maximumTextWidth, CGFLOAT_MAX)
                         options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading)
                      attributes:@{
                                   NSFontAttributeName : [UIFont ows_dynamicTypeBodyFont]
                      } // Hack to use a slightly larger than actual font, because I'm seeing messages with higher line count get clipped.
                         context:nil];
        // END InfoMessage sizing HACK
        ////////////////////

        CGSize stringSize = CGRectIntegral(stringRect).size;

        CGFloat verticalContainerInsets = layout.messageBubbleTextViewTextContainerInsets.top
            + layout.messageBubbleTextViewTextContainerInsets.bottom;

        CGFloat verticalFrameInsets
            = layout.messageBubbleTextViewFrameInsets.top + layout.messageBubbleTextViewFrameInsets.bottom;
        ///////////////////
        // BEGIN InfoMessage sizing HACK

        CGFloat topIconPortrusion = 28;

        verticalFrameInsets += topIconPortrusion;

        // END InfoMessage sizing HACK
        ///////////////////

        //  add extra 2 points of space (`self.additionalInset`), because `boundingRectWithSize:` is slightly off
        //  not sure why. magix. (shrug) if you know, submit a PR
        CGFloat verticalInsets = verticalContainerInsets + verticalFrameInsets + self.additionalInset;

        //  same as above, an extra 2 points of magix
        CGFloat finalWidth
            = MAX(stringSize.width + horizontalInsetsTotal, self.minimumBubbleWidth) + self.additionalInset;

        finalSize = CGSizeMake(finalWidth, stringSize.height + verticalInsets);
    }

    [self.cache setObject:[NSValue valueWithCGSize:finalSize] forKey:@([messageData messageHash])];

    return finalSize;
}

- (CGSize)messageBubbleSizeForCallData:(id<JSQMessageData>)messageData
                           atIndexPath:(NSIndexPath *)indexPath
                            withLayout:(JSQMessagesCollectionViewFlowLayout *)layout
{
    NSValue *cachedSize = [self.cache objectForKey:@([messageData messageHash])];
    if (cachedSize != nil) {
        return [cachedSize CGSizeValue];
    }

    CGFloat horizontalInsetsTotal = 0.0;
    CGFloat maximumTextWidth = [self textBubbleWidthForLayout:layout] - horizontalInsetsTotal;

    CGRect stringRect = [[messageData text]
        boundingRectWithSize:CGSizeMake(maximumTextWidth, CGFLOAT_MAX)
                     options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading)
                  attributes:@{
                      NSFontAttributeName : [UIFont ows_dynamicTypeBodyFont]
                  } // Hack to use a slightly larger than actual font, because I'm seeing messages with higher line
                    // count get clipped.
                     context:nil];

    CGSize stringSize = CGRectIntegral(stringRect).size;

    CGFloat verticalInsets = 0;
    CGFloat finalWidth = maximumTextWidth + horizontalInsetsTotal;

    CGSize finalSize = CGSizeMake(finalWidth, stringSize.height + verticalInsets);

    [self.cache setObject:[NSValue valueWithCGSize:finalSize] forKey:@([messageData messageHash])];

    return finalSize;
}

@end

NS_ASSUME_NONNULL_END
