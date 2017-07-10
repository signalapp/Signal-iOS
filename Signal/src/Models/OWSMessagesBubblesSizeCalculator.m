//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessagesBubblesSizeCalculator.h"
#import "OWSCall.h"
#import "OWSSystemMessageCell.h"
#import "OWSUnreadIndicatorCell.h"
#import "TSGenericAttachmentAdapter.h"
#import "TSMessageAdapter.h"
#import "TSUnreadIndicatorInteraction.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import "tgmath.h" // generic math allows fmax to handle CGFLoat correctly on 32 & 64bit.
#import <JSQMessagesViewController/JSQMessagesCollectionView.h>
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

#pragma mark -

@interface OWSMessagesBubblesSizeCalculator ()

@property (nonatomic, readonly) OWSSystemMessageCell *referenceSystemMessageCell;
@property (nonatomic, readonly) OWSUnreadIndicatorCell *referenceUnreadIndicatorCell;

@end

#pragma mark -

@implementation OWSMessagesBubblesSizeCalculator

- (instancetype)init
{
    if (self = [super init]) {
        _referenceSystemMessageCell = [OWSSystemMessageCell new];
        _referenceUnreadIndicatorCell = [OWSUnreadIndicatorCell new];
    }
    return self;
}

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

        switch (message.messageType) {
            case TSCallAdapter:
            case TSInfoMessageAdapter:
            case TSErrorMessageAdapter: {
                id cacheKey = [self cacheKeyForMessageData:messageData];
                TSInteraction *interaction = ((TSMessageAdapter *)messageData).interaction;
                return [self sizeForSystemMessage:interaction cacheKey:cacheKey layout:layout];
            }
            case TSUnreadIndicatorAdapter: {
                id cacheKey = [self cacheKeyForMessageData:messageData];
                TSUnreadIndicatorInteraction *interaction
                    = (TSUnreadIndicatorInteraction *)((TSMessageAdapter *)messageData).interaction;
                return [self sizeForUnreadIndicator:interaction cacheKey:cacheKey layout:layout];
            }
            case TSIncomingMessageAdapter:
            case TSOutgoingMessageAdapter:
                break;
            default:
                OWSFail(@"Unknown sizing interaction: %@", [((TSMessageAdapter *)messageData).interaction class]);
                break;
        }
    } else if ([messageData isKindOfClass:[OWSCall class]]) {
        id cacheKey = [self cacheKeyForMessageData:messageData];
        TSInteraction *interaction = ((OWSCall *)messageData).interaction;
        return [self sizeForSystemMessage:interaction cacheKey:cacheKey layout:layout];
    } else {
        // Ignore unknown message types; the tests use mocks.
    }

    // BEGIN HACK iOS10EmojiBug see: https://github.com/WhisperSystems/Signal-iOS/issues/1368
    if ([self shouldApplyiOS10EmojiFixToString:messageData.text font:layout.messageBubbleFont]) {
        return [self withiOS10EmojiFixSuperMessageBubbleSizeForMessageData:messageData
                                                               atIndexPath:indexPath
                                                                withLayout:layout];
    } else {
        // END HACK iOS10EmojiBug see: https://github.com/WhisperSystems/Signal-iOS/issues/1368

        return [super messageBubbleSizeForMessageData:messageData atIndexPath:indexPath withLayout:layout];
    }
}

- (CGSize)sizeForSystemMessage:(TSInteraction *)interaction
                      cacheKey:(id)cacheKey
                        layout:(JSQMessagesCollectionViewFlowLayout *)layout
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(interaction);
    OWSAssert(cacheKey);

    NSValue *cachedSize = [self.cache objectForKey:cacheKey];
    if (cachedSize != nil) {
        return [cachedSize CGSizeValue];
    }

    CGSize result = [self.referenceSystemMessageCell bubbleSizeForInteraction:interaction
                                                          collectionViewWidth:layout.collectionView.width];

    [self.cache setObject:[NSValue valueWithCGSize:result] forKey:cacheKey];

    return result;
}

- (CGSize)sizeForUnreadIndicator:(TSUnreadIndicatorInteraction *)interaction
                        cacheKey:(id)cacheKey
                          layout:(JSQMessagesCollectionViewFlowLayout *)layout
{
    OWSAssert(interaction);
    OWSAssert(cacheKey);

    NSValue *cachedSize = [self.cache objectForKey:cacheKey];
    if (cachedSize != nil) {
        return [cachedSize CGSizeValue];
    }

    CGSize result = [self.referenceUnreadIndicatorCell bubbleSizeForInteraction:interaction
                                                            collectionViewWidth:layout.collectionView.width];

    [self.cache setObject:[NSValue valueWithCGSize:result] forKey:cacheKey];

    return result;
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
    // This is a crappy solution. Long messages with only one line of emoji will have an extra pixel per line.
    return CGSizeMake(superSize.width, superSize.height + (CGFloat)1.5 * lines);
}

- (id)cacheKeyForMessageData:(id<JSQMessageData>)messageData
{
    OWSAssert(messageData);
    OWSAssert([messageData conformsToProtocol:@protocol(OWSMessageData)]);
    OWSAssert(((id<OWSMessageData>)messageData).interaction);
    OWSAssert(((id<OWSMessageData>)messageData).interaction.uniqueId);

    return @([messageData messageHash]);
}

@end

NS_ASSUME_NONNULL_END
