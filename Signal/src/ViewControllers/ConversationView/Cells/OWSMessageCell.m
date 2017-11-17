//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageCell.h"
#import "AttachmentSharing.h"
#import "AttachmentUploadView.h"
#import "ConversationViewItem.h"
#import "NSAttributedString+OWS.h"
#import "OWSAudioMessageView.h"
#import "OWSExpirationTimerView.h"
#import "OWSGenericAttachmentView.h"
#import "Signal-Swift.h"
#import "UIColor+OWS.h"
#import <JSQMessagesViewController/JSQMessagesTimestampFormatter.h>
#import <JSQMessagesViewController/UIColor+JSQMessages.h>
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

// TODO: Choose best thorn.
// TODO: Review all comments.

CG_INLINE CGSize CGSizeCeil(CGSize size)
{
    return CGSizeMake((CGFloat)ceil(size.width), (CGFloat)ceil(size.height));
}

// This approximates the curve of our message bubbles, which makes the animation feel a little smoother.
const CGFloat OWSMessageCellCornerRadius = 17;

// TODO: We could make the bubble shape respond to dynamic text.
static const CGFloat kBubbleVRounding =  8.5f;
static const CGFloat kBubbleHRounding = 10.f;
//static const CGFloat kBubbleThornSideInset = 3.f;
//static const CGFloat kBubbleThornVInset = 3.f;
//static const CGFloat kBubbleThornSideInset = 6.f;
//static const CGFloat kBubbleThornVInset = 0.f;
static const CGFloat kBubbleThornSideInset = kBubbleHRounding * 0.3f;
static const CGFloat kBubbleThornVInset = kBubbleVRounding * 0.3f;
static const CGFloat kBubbleTextHInset = 6.f;
static const CGFloat kBubbleTextVInset = 6.f;

@interface OWSBubbleView : UIView

@property (nonatomic) BOOL isOutgoing;
@property (nonatomic) BOOL hideTail;
//@property (nonatomic, nullable, weak) UIView *maskedSubview;
@property (nonatomic) CAShapeLayer *maskLayer;

//@property (nonatomic) BOOL isOutgoing;
@property (nonatomic) CAShapeLayer *shapeLayer;
@property (nonatomic) UIColor *bubbleColor;

@end

#pragma mark -

@implementation OWSBubbleView

- (void)setIsOutgoing:(BOOL)isOutgoing {
    BOOL didChange = _isOutgoing != isOutgoing;

    _isOutgoing = isOutgoing;

    if (didChange || !self.shapeLayer) {
        [self updateMask];
    }
}

- (void)setFrame:(CGRect)frame
{
    BOOL didChange = !CGSizeEqualToSize(self.frame.size, frame.size);

    [super setFrame:frame];

    if (didChange || !self.shapeLayer) {
        [self updateMask];
    }
}

- (void)setBounds:(CGRect)bounds
{
    BOOL didChange = !CGSizeEqualToSize(self.bounds.size, bounds.size);

    [super setBounds:bounds];

    if (didChange || !self.shapeLayer) {
        [self updateMask];
    }
}

- (void)setBubbleColor:(UIColor *)bubbleColor
{
    _bubbleColor = bubbleColor;

    if (!self.shapeLayer) {
        [self updateMask];
    }
    self.shapeLayer.fillColor = bubbleColor.CGColor;
}

- (void)updateMask
{
    if (!self.shapeLayer) {
        self.shapeLayer = [CAShapeLayer new];
        [self.layer addSublayer:self.shapeLayer];
    }
    if (!self.maskLayer) {
        self.maskLayer = [CAShapeLayer new];
        self.layer.mask = self.maskLayer;
    }

    UIBezierPath *bezierPath = [self.class maskPathForSize:self.bounds.size
                                                isOutgoing:self.isOutgoing
                                                     isRTL:self.isRTL];

    self.shapeLayer.fillColor = self.bubbleColor.CGColor;
    self.shapeLayer.path = bezierPath.CGPath;

    self.maskLayer.path = bezierPath.CGPath;
}

//- (void)updateMask
//{
//    UIView *_Nullable maskedSubview = self.maskedSubview;
//    if (!maskedSubview) {
//        return;
//    }
//    maskedSubview.frame = self.bounds;
//    //<<<<<<< HEAD
//    //    // The JSQ masks are not RTL-safe, so we need to invert the
//    //    // mask orientation manually.
//    //    BOOL hasOutgoingMask = self.isOutgoing ^ self.isRTL;
//    //
//    //    // Since the caption has it's own tail, the media bubble just above
//    //    // it looks better without a tail.
//    //    if (self.hideTail) {
//    //        if (hasOutgoingMask) {
//    //            self.layoutMargins = UIEdgeInsetsMake(0, 0, 2, 8);
//    //        } else {
//    //            self.layoutMargins = UIEdgeInsetsMake(0, 8, 2, 0);
//    //        }
//    //        maskedSubview.clipsToBounds = YES;
//    //
//    //        // I arrived at this cornerRadius by superimposing the generated corner
//    //        // over that generated from the JSQMessagesMediaViewBubbleImageMasker
//    //        maskedSubview.layer.cornerRadius = 17;
//    //    } else {
//    //        [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:maskedSubview
//    //                                                                    isOutgoing:hasOutgoingMask];
//    //    }
//    //||||||| merged common ancestors
//    //    // The JSQ masks are not RTL-safe, so we need to invert the
//    //    // mask orientation manually.
//    //    BOOL hasOutgoingMask = self.isOutgoing ^ self.isRTL;
//    //    [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:maskedSubview
//    isOutgoing:hasOutgoingMask];
//    //=======
//
//
//    UIBezierPath *bezierPath = [BubbleFillView maskPathForSize:self.bounds.size
//                                                    isOutgoing:self.isOutgoing
//                                                         isRTL:self.isRTL];
//    self.maskLayer.path = bezierPath.CGPath;
//    maskedSubview.layer.mask = self.maskLayer;
//    //>>>>>>> SQUASHED
//}

//- (void)setIsOutgoing:(BOOL)isOutgoing {
//    if (_isOutgoing == isOutgoing) {
//        return;
//    }
//    _isOutgoing = isOutgoing;
//    [self updateMask];
//}
//
//- (void)setFrame:(CGRect)frame
//{
//    BOOL didSizeChange = !CGSizeEqualToSize(self.frame.size, frame.size);
//
//    [super setFrame:frame];
//
//    if (didSizeChange || !self.shapeLayer) {
//        [self updateMask];
//    }
//}
//
//- (void)setBounds:(CGRect)bounds
//{
//    BOOL didSizeChange = !CGSizeEqualToSize(self.bounds.size, bounds.size);
//
//    [super setBounds:bounds];
//
//    if (didSizeChange || !self.shapeLayer) {
//        [self updateMask];
//    }
//}
//
//- (void)updateMask
//{
//    if (!self.shapeLayer) {
//        self.shapeLayer = [CAShapeLayer new];
//        [self.layer addSublayer:self.shapeLayer];
//    }
//
//    UIBezierPath *bezierPath = [self.class maskPathForSize:self.bounds.size
//                                                isOutgoing:self.isOutgoing
//                                                     isRTL:self.isRTL];
//
//    self.shapeLayer.fillColor = self.bubbleColor.CGColor;
//    self.shapeLayer.path = bezierPath.CGPath;
//}

+ (UIBezierPath *)maskPathForSize:(CGSize)size
                       isOutgoing:(BOOL)isOutgoing
                            isRTL:(BOOL)isRTL
{
    UIBezierPath *bezierPath = [UIBezierPath new];
    
    CGFloat bubbleLeft = 0.f;
    CGFloat bubbleRight = size.width - kBubbleThornSideInset;
    CGFloat bubbleTop = 0.f;
    CGFloat bubbleBottom = size.height - kBubbleThornVInset;
    
    [bezierPath moveToPoint:CGPointMake(bubbleLeft + kBubbleHRounding, bubbleTop)];
    [bezierPath addLineToPoint:CGPointMake(bubbleRight - kBubbleHRounding, bubbleTop)];
    [bezierPath addQuadCurveToPoint:CGPointMake(bubbleRight, bubbleTop + kBubbleVRounding)
                       controlPoint:CGPointMake(bubbleRight, bubbleTop)];
    [bezierPath addLineToPoint:CGPointMake(bubbleRight, bubbleBottom - kBubbleVRounding)];
    [bezierPath addQuadCurveToPoint:CGPointMake(bubbleRight - kBubbleHRounding, bubbleBottom)
                       controlPoint:CGPointMake(bubbleRight, bubbleBottom)];
    [bezierPath addLineToPoint:CGPointMake(bubbleLeft + kBubbleHRounding, bubbleBottom)];
    [bezierPath addQuadCurveToPoint:CGPointMake(bubbleLeft, bubbleBottom - kBubbleVRounding)
                       controlPoint:CGPointMake(bubbleLeft, bubbleBottom)];
    [bezierPath addLineToPoint:CGPointMake(bubbleLeft, bubbleTop + kBubbleVRounding)];
    [bezierPath addQuadCurveToPoint:CGPointMake(bubbleLeft + kBubbleHRounding, bubbleTop)
                       controlPoint:CGPointMake(bubbleLeft, bubbleTop)];
    
    // Thorn Tip
    CGPoint thornTip = CGPointMake(size.width,
                                   size.height);
    CGPoint thornA = CGPointMake(bubbleRight - kBubbleHRounding, bubbleBottom);
    CGPoint thornB = CGPointMake(bubbleRight, bubbleBottom - kBubbleVRounding);
    [bezierPath moveToPoint:thornTip];
    //    [bezierPath addLineToPoint:CGPointMake(bubbleRight - kBubbleHRounding * 0.85f, bubbleBottom)];
    //    [bezierPath addLineToPoint:thornA];
    //    [bezierPath addLineToPoint:thornB];
    //    [bezierPath addLineToPoint:CGPointMake(bubbleRight, bubbleBottom - kBubbleVRounding * 0.5f)];
    [bezierPath addQuadCurveToPoint:CGPointMake(bubbleRight - kBubbleHRounding * 0.8f, bubbleBottom)
                       controlPoint:CGPointMake(bubbleRight - kBubbleHRounding * 0.4f, bubbleBottom)];
    [bezierPath addLineToPoint:thornA];
    [bezierPath addLineToPoint:thornB];
    [bezierPath addLineToPoint:CGPointMake(bubbleRight, bubbleBottom - kBubbleVRounding * 0.7f)];
    [bezierPath addQuadCurveToPoint:thornTip
                       controlPoint:CGPointMake(bubbleRight, bubbleBottom - kBubbleVRounding * 0.3f)];

    //    // Thorn Tip
    //    [bezierPath moveToPoint:CGPointMake(bubbleRight - kBubbleHRounding, bubbleBottom)];
    //    [bezierPath addLineToPoint:CGPointMake(bubbleRight, bubbleBottom - kBubbleVRounding)];
    //    [bezierPath addQuadCurveToPoint:CGPointMake(bubbleRight + kBubbleThornSideInset, bubbleBottom - 0.f)
    //                       controlPoint:CGPointMake(bubbleRight, bubbleBottom)];
    //    //    [bezierPath addQuadCurveToPoint:CGPointMake(bubbleRight + kBubbleThornSideInset - 1.f, bubbleBottom -
    //    0.5f)
    //    //                       controlPoint:CGPointMake(bubbleRight, bubbleBottom)];
    //    //    [bezierPath addQuadCurveToPoint:CGPointMake(bubbleRight + kBubbleThornSideInset, bubbleBottom)
    //    //                       controlPoint:CGPointMake(bubbleRight + kBubbleThornSideInset, bubbleBottom - 0.5f)];
    //    [bezierPath addLineToPoint:CGPointMake(bubbleRight + kBubbleThornSideInset, bubbleBottom)];

    //    // Thorn Tip
    //    CGFloat kThornPinchingA = 0.f;
    //    CGFloat kThornPinchingB = 3.5f;
    //    CGPoint thornTip = CGPointMake(self.width,
    //                                   self.height);
    //    CGPoint thornA = CGPointMake(bubbleRight - kBubbleHRounding, bubbleBottom - kThornPinchingA);
    //    CGPoint thornB = CGPointMake(bubbleRight - kThornPinchingB, bubbleBottom - kBubbleVRounding);
    //    [bezierPath moveToPoint:thornTip];
    //    [bezierPath addQuadCurveToPoint:thornA
    //                       controlPoint:CGPointMake(bubbleRight - kBubbleHRounding, bubbleBottom - kThornPinchingA)];
    //    [bezierPath addLineToPoint:thornB];
    //    [bezierPath addQuadCurveToPoint:thornTip
    //                       controlPoint:CGPointMake(bubbleRight - kThornPinchingB, bubbleBottom - kBubbleVRounding * 0.1f)];
    
    // Thorn Tip
    //    CGFloat kThornPinchingA = 0.f;
    //    CGFloat kThornPinchingB = 3.5f;
    //    CGPoint thornA = CGPointMake(bubbleRight, bubbleBottom - kBubbleVRounding * 1.65f);
    //    CGPoint thornB = CGPointMake(bubbleRight, bubbleBottom - kBubbleVRounding * 1.f);
    
    //    CGPoint thornA = CGPointMake(bubbleRight, bubbleTop + kBubbleVRounding * 1.f);
    //    CGPoint thornB = CGPointMake(bubbleRight, bubbleTop + kBubbleVRounding * 1.65f);
    //    CGPoint thornTip = CGPointMake(bubbleRight + kBubbleThornSideInset * 0.85f,
    //                                   (thornA.y + thornB.y) * 0.5f);
    //    [bezierPath moveToPoint:thornTip];
    //    [bezierPath addLineToPoint:thornA];
    //    [bezierPath addLineToPoint:thornB];
    
    //    [bezierPath addQuadCurveToPoint:thornA
    //                       controlPoint:CGPointMake(bubbleRight - kBubbleHRounding, bubbleBottom - kThornPinchingA)];
    //    [bezierPath addLineToPoint:thornB];
    //    [bezierPath addQuadCurveToPoint:thornTip
    //                       controlPoint:CGPointMake(bubbleRight - kThornPinchingB, bubbleBottom - kBubbleVRounding * 0.1f)];
    
    // Horizontal Flip If Necessary
    BOOL shouldFlip = isOutgoing == isRTL;
    if (shouldFlip) {
        CGAffineTransform flipTransform = CGAffineTransformMakeTranslation(size.width, 0.0);
        flipTransform = CGAffineTransformScale(flipTransform, -1.0, 1.0);
        [bezierPath applyTransform:flipTransform];
    }
    return bezierPath;
}

//- (void)setBubbleColor:(UIColor *)bubbleColor {
//    _bubbleColor = bubbleColor;
//
//    self.shapeLayer.fillColor = bubbleColor.CGColor;
//}

@end

#pragma mark -

//@interface BubbleFillView : UIView
//
////@property (nonatomic) BOOL isOutgoing;
////@property (nonatomic) CAShapeLayer *shapeLayer;
////@property (nonatomic) UIColor *bubbleColor;
//
//@end
//
//#pragma mark -
//
//@implementation BubbleFillView
//
////- (void)setIsOutgoing:(BOOL)isOutgoing {
////    if (_isOutgoing == isOutgoing) {
////        return;
////    }
////    _isOutgoing = isOutgoing;
////    [self updateMask];
////}
////
////- (void)setFrame:(CGRect)frame
////{
////    BOOL didSizeChange = !CGSizeEqualToSize(self.frame.size, frame.size);
////
////    [super setFrame:frame];
////
////    if (didSizeChange || !self.shapeLayer) {
////        [self updateMask];
////    }
////}
////
////- (void)setBounds:(CGRect)bounds
////{
////    BOOL didSizeChange = !CGSizeEqualToSize(self.bounds.size, bounds.size);
////
////    [super setBounds:bounds];
////
////    if (didSizeChange || !self.shapeLayer) {
////        [self updateMask];
////    }
////}
////
////- (void)updateMask
////{
////    if (!self.shapeLayer) {
////        self.shapeLayer = [CAShapeLayer new];
////        [self.layer addSublayer:self.shapeLayer];
////    }
////
////    UIBezierPath *bezierPath = [self.class maskPathForSize:self.bounds.size
////                                                isOutgoing:self.isOutgoing
////                                                     isRTL:self.isRTL];
////
////    self.shapeLayer.fillColor = self.bubbleColor.CGColor;
////    self.shapeLayer.path = bezierPath.CGPath;
////}
//
////- (void)setBubbleColor:(UIColor *)bubbleColor {
////    _bubbleColor = bubbleColor;
////
////    self.shapeLayer.fillColor = bubbleColor.CGColor;
////}
//
//@end
//
//#pragma mark -
//
//@interface BubbleMaskingView : UIView
//
//@property (nonatomic) BOOL isOutgoing;
//@property (nonatomic) BOOL hideTail;
//@property (nonatomic, nullable, weak) UIView *maskedSubview;
//@property (nonatomic) CAShapeLayer *maskLayer;
//
//@end
//
//#pragma mark -
//
//@implementation BubbleMaskingView
//
//- (void)setMaskedSubview:(UIView * _Nullable)maskedSubview {
//    if (_maskedSubview == maskedSubview) {
//        return;
//    }
//    _maskedSubview = maskedSubview;
//    [self updateMask];
//}
//
//- (void)setIsOutgoing:(BOOL)isOutgoing {
//    if (_isOutgoing == isOutgoing) {
//        return;
//    }
//    _isOutgoing = isOutgoing;
//    [self updateMask];
//}
//
//- (void)setFrame:(CGRect)frame
//{
//    BOOL didSizeChange = !CGSizeEqualToSize(self.frame.size, frame.size);
//
//    [super setFrame:frame];
//
//    if (didSizeChange) {
//        [self updateMask];
//    }
//}
//
//- (void)setBounds:(CGRect)bounds
//{
//    BOOL didSizeChange = !CGSizeEqualToSize(self.bounds.size, bounds.size);
//
//    [super setBounds:bounds];
//
//    if (didSizeChange) {
//        [self updateMask];
//    }
//}
//
//- (void)updateMask
//{
//    UIView *_Nullable maskedSubview = self.maskedSubview;
//    if (!maskedSubview) {
//        return;
//    }
//    maskedSubview.frame = self.bounds;
//    //<<<<<<< HEAD
//    //    // The JSQ masks are not RTL-safe, so we need to invert the
//    //    // mask orientation manually.
//    //    BOOL hasOutgoingMask = self.isOutgoing ^ self.isRTL;
//    //
//    //    // Since the caption has it's own tail, the media bubble just above
//    //    // it looks better without a tail.
//    //    if (self.hideTail) {
//    //        if (hasOutgoingMask) {
//    //            self.layoutMargins = UIEdgeInsetsMake(0, 0, 2, 8);
//    //        } else {
//    //            self.layoutMargins = UIEdgeInsetsMake(0, 8, 2, 0);
//    //        }
//    //        maskedSubview.clipsToBounds = YES;
//    //
//    //        // I arrived at this cornerRadius by superimposing the generated corner
//    //        // over that generated from the JSQMessagesMediaViewBubbleImageMasker
//    //        maskedSubview.layer.cornerRadius = 17;
//    //    } else {
//    //        [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:maskedSubview
//    //                                                                    isOutgoing:hasOutgoingMask];
//    //    }
//    //||||||| merged common ancestors
//    //    // The JSQ masks are not RTL-safe, so we need to invert the
//    //    // mask orientation manually.
//    //    BOOL hasOutgoingMask = self.isOutgoing ^ self.isRTL;
//    //    [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:maskedSubview
//    isOutgoing:hasOutgoingMask];
//    //=======
//
//    if (!self.maskLayer) {
//        self.maskLayer = [CAShapeLayer new];
//    }
//
//    UIBezierPath *bezierPath = [OWSBubbleView maskPathForSize:self.bounds.size
//                                                   isOutgoing:self.isOutgoing
//                                                        isRTL:self.isRTL];
//    self.maskLayer.path = bezierPath.CGPath;
//    maskedSubview.layer.mask = self.maskLayer;
//    //>>>>>>> SQUASHED
//}
//
//@end

#pragma mark -

@interface OWSMessageTextView : UITextView

@property (nonatomic) BOOL shouldIgnoreEvents;

@end

#pragma mark -

@implementation OWSMessageTextView

// Our message text views are never used for editing;
// suppress their ability to become first responder
// so that tapping on them doesn't hide keyboard.
- (BOOL)canBecomeFirstResponder
{
    return NO;
}

// Ignore interactions with the text view _except_ taps on links.
//
// We want to disable "partial" selection of text in the message
// and we want to enable "tap to resend" by tapping on a message.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *_Nullable)event
{
    if (self.shouldIgnoreEvents) {
        // We ignore all events for failed messages so that users
        // can tap-to-resend even "all link" messages.
        return NO;
    }

    // Find the nearest text position to the event.
    UITextPosition *_Nullable position = [self closestPositionToPoint:point];
    if (!position) {
        return NO;
    }
    // Find the range of the character in the text which contains the event.
    //
    // Try every layout direction (this might not be necessary).
    UITextRange *_Nullable range = nil;
    for (NSNumber *textLayoutDirection in @[
             @(UITextLayoutDirectionLeft),
             @(UITextLayoutDirectionRight),
             @(UITextLayoutDirectionUp),
             @(UITextLayoutDirectionDown),
         ]) {
        range = [self.tokenizer rangeEnclosingPosition:position
                                       withGranularity:UITextGranularityCharacter
                                           inDirection:(UITextDirection)textLayoutDirection.intValue];
        if (range) {
            break;
        }
    }
    if (!range) {
        return NO;
    }
    // Ignore the event unless it occurred inside a link.
    NSInteger startIndex = [self offsetFromPosition:self.beginningOfDocument toPosition:range.start];
    BOOL result =
        [self.attributedText attribute:NSLinkAttributeName atIndex:(NSUInteger)startIndex effectiveRange:nil] != nil;
    return result;
}

@end

#pragma mark -

@interface OWSMessageCell ()

// The nullable properties are created as needed.
// The non-nullable properties are so frequently used that it's easier
// to always keep one around.

// The contentView contains:
//
// * MessageView (message)
// * dateHeaderLabel (above message)
// * footerView (below message)
// * failedSendBadgeView (beside message)

@property (nonatomic) OWSBubbleView *bubbleView;

//@property (nonatomic) UIView *messageWrapperView;


//@property (nonatomic) UIView *payloadView;
//@property (nonatomic) BubbleMaskingView *bubbleView;
////@property (nonatomic) BubbleMaskingView *mediaMaskingView;
@property (nonatomic) UILabel *dateHeaderLabel;
@property (nonatomic) OWSMessageTextView *bodyTextViewCached;
@property (nonatomic, nullable) UIImageView *failedSendBadgeView;
//@property (nonatomic, nullable) UILabel *tapForMoreLabel;
////<<<<<<< HEAD
////@property (nonatomic, nullable) UIImageView *textBubbleImageView;
////||||||| merged common ancestors
////@property (nonatomic, nullable) UIImageView *bubbleImageView;
////=======
////@property (nonatomic, nullable) BubbleFillView *bubbleFillView;
//////@property (nonatomic, nullable) UIImageView *bubbleImageView;
////>>>>>>> SQUASHED
//@property (nonatomic, nullable) AttachmentUploadView *attachmentUploadView;
//@property (nonatomic, nullable) UIImageView *stillImageView;
//@property (nonatomic, nullable) YYAnimatedImageView *animatedImageView;
//@property (nonatomic, nullable) UIView *customView;
//@property (nonatomic, nullable) AttachmentPointerView *attachmentPointerView;
//@property (nonatomic, nullable) OWSGenericAttachmentView *attachmentView;
//@property (nonatomic, nullable) OWSAudioMessageView *audioMessageView;
@property (nonatomic) UIView *footerView;
@property (nonatomic) UILabel *footerLabel;
@property (nonatomic, nullable) OWSExpirationTimerView *expirationTimerView;

@property (nonatomic, nullable) UIImageView *lastImageView;

// Should lazy-load expensive view contents (images, etc.).
// Should do nothing if view is already loaded.
@property (nonatomic, nullable) dispatch_block_t loadCellContentBlock;
// Should unload all expensive view contents (images, etc.).
@property (nonatomic, nullable) dispatch_block_t unloadCellContentBlock;

// TODO: Review
// TODO: Rename to cellcont
@property (nonatomic, nullable) NSArray<NSLayoutConstraint *> *cellContentConstraints;
@property (nonatomic, nullable) NSArray<NSLayoutConstraint *> *dateHeaderConstraints;
@property (nonatomic, nullable) NSMutableArray<NSLayoutConstraint *> *bubbleContentConstraints;
@property (nonatomic, nullable) NSArray<NSLayoutConstraint *> *footerConstraints;
@property (nonatomic) BOOL isPresentingMenuController;


@end

@implementation OWSMessageCell

// `[UIView init]` invokes `[self initWithFrame:...]`.
- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self commontInit];
    }

    return self;
}

- (void)commontInit
{
    OWSAssert(!self.bodyTextViewCached);

    _bubbleContentConstraints = [NSMutableArray new];

    self.layoutMargins = UIEdgeInsetsZero;
    self.contentView.layoutMargins = UIEdgeInsetsZero;

    self.bubbleView = [OWSBubbleView new];
    self.bubbleView.layoutMargins = UIEdgeInsetsZero;
    [self.contentView addSubview:self.bubbleView];

    //    self.messageWrapperView = [UIView new];
    //    self.messageWrapperView.layoutMargins = UIEdgeInsetsZero;
    //    [self.messageWrapperView addSubview:self.payloadView];
    //    self.payloadView = [UIView new];
    //    self.payloadView.layoutMargins = UIEdgeInsetsZero;
    //    [self.contentView addSubview:self.payloadView];

    //    self.mediaMaskingView = [BubbleMaskingView new];
    //    self.mediaMaskingView.layoutMargins = UIEdgeInsetsZero;
    //    [self.payloadView addSubview:self.mediaMaskingView];

    self.footerView = [UIView containerView];
    [self.contentView addSubview:self.footerView];

    self.dateHeaderLabel = [UILabel new];
    self.dateHeaderLabel.font = [UIFont ows_regularFontWithSize:12.f];
    self.dateHeaderLabel.textAlignment = NSTextAlignmentCenter;
    self.dateHeaderLabel.textColor = [UIColor lightGrayColor];
    [self.contentView addSubview:self.dateHeaderLabel];

    //<<<<<<< HEAD
    //    self.textBubbleImageView = [UIImageView new];
    //    self.textBubbleImageView.layoutMargins = UIEdgeInsetsZero;
    //    // Enable userInteractionEnabled so that links in textView work.
    //    self.textBubbleImageView.userInteractionEnabled = YES;
    //
    //    [self.payloadView addSubview:self.textBubbleImageView];
    //
    //||||||| merged common ancestors
    //    self.bubbleImageView = [UIImageView new];
    //    self.bubbleImageView.layoutMargins = UIEdgeInsetsZero;
    //    // Enable userInteractionEnabled so that links in textView work.
    //    self.bubbleImageView.userInteractionEnabled = YES;
    //    [self.payloadView addSubview:self.bubbleImageView];
    //    [self.bubbleImageView autoPinToSuperviewEdges];
    //
    //=======
    //    self.bubbleFillView = [BubbleFillView new];
    //    self.bubbleFillView.layoutMargins = UIEdgeInsetsZero;
    //    // TODO:
    ////    // Enable userInteractionEnabled so that links in textView work.
    //    self.bubbleFillView.userInteractionEnabled = YES;
    //    [self.payloadView addSubview:self.bubbleFillView];
    //    [self.bubbleFillView autoPinToSuperviewEdges];
    //
    ////    self.bubbleImageView = [UIImageView new];
    ////    self.bubbleImageView.layoutMargins = UIEdgeInsetsZero;
    ////    // Enable userInteractionEnabled so that links in textView work.
    ////    self.bubbleImageView.userInteractionEnabled = YES;
    ////    [self.payloadView addSubview:self.bubbleImageView];
    ////    [self.bubbleImageView autoPinToSuperviewEdges];
    //
    //>>>>>>> SQUASHED
    self.bodyTextViewCached = [self newTextView];
    //<<<<<<< HEAD
    //
    //    [self.textBubbleImageView addSubview:self.textView];
    //
    //||||||| merged common ancestors
    //    [self.bubbleImageView addSubview:self.textView];
    //=======
    //    [self.bubbleFillView addSubview:self.textView];
    //>>>>>>> SQUASHED
    //    OWSAssert(self.textView.superview);

    self.footerLabel = [UILabel new];
    self.footerLabel.font = [UIFont ows_regularFontWithSize:12.f];
    self.footerLabel.textColor = [UIColor lightGrayColor];
    [self.footerView addSubview:self.footerLabel];

    // Hide these views by default.
    //<<<<<<< HEAD
    //    self.textBubbleImageView.hidden = YES;
    //||||||| merged common ancestors
    //    self.bubbleImageView.hidden = YES;
    //=======
    //    self.bubbleFillView.hidden = YES;
    ////    self.bubbleImageView.hidden = YES;
    //>>>>>>> SQUASHED
    self.bodyTextViewCached.hidden = YES;
    self.dateHeaderLabel.hidden = YES;
    self.footerLabel.hidden = YES;

    [self.bubbleView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.dateHeaderLabel];
    [self.footerView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.bubbleView];

    //    [self.payloadView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.dateHeaderLabel];
    //    [self.footerView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.bubbleView];

    //    [self.mediaMaskingView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    //
    //    [self.textBubbleImageView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.mediaMaskingView];
    //    [self.textBubbleImageView autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    [self.footerView autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [self.footerView autoPinWidthToSuperview];

    //    UITapGestureRecognizer *mediaTap =
    //        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleMediaTapGesture:)];
    //    [self.mediaMaskingView addGestureRecognizer:mediaTap];
    //
    //    UITapGestureRecognizer *textTap =
    //        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTextTapGesture:)];
    //    [self.textBubbleImageView addGestureRecognizer:textTap];
    //
    //    UILongPressGestureRecognizer *mediaLongPress =
    //        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleMediaLongPressGesture:)];
    //    [self.mediaMaskingView addGestureRecognizer:mediaLongPress];
    //
    //    UILongPressGestureRecognizer *textLongPress =
    //        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleTextLongPressGesture:)];
    //    [self.textBubbleImageView addGestureRecognizer:textLongPress];
    //
    //    PanDirectionGestureRecognizer *panGesture =
    //        [[PanDirectionGestureRecognizer alloc] initWithDirection:(self.isRTL ? PanDirectionLeft :
    //        PanDirectionRight)
    //                                                          target:self
    //                                                          action:@selector(handlePanGesture:)];
    //    [self addGestureRecognizer:panGesture];
}

- (OWSMessageTextView *)newTextView
{
    OWSMessageTextView *textView = [OWSMessageTextView new];
    textView.backgroundColor = [UIColor clearColor];
    textView.opaque = NO;
    textView.editable = NO;
    textView.selectable = YES;
    textView.textContainerInset = UIEdgeInsetsZero;
    textView.contentInset = UIEdgeInsetsZero;
    textView.scrollEnabled = NO;
    return textView;
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (UIFont *)textMessageFont
{
    OWSAssert(DisplayableText.kMaxJumbomojiCount == 5);

    CGFloat basePointSize = [UIFont ows_dynamicTypeBodyFont].pointSize;
    switch (self.displayableText.jumbomojiCount) {
        case 0:
            break;
        case 1:
            return [UIFont ows_regularFontWithSize:basePointSize + 18.f];
        case 2:
            return [UIFont ows_regularFontWithSize:basePointSize + 12.f];
        case 3:
        case 4:
        case 5:
            return [UIFont ows_regularFontWithSize:basePointSize + 6.f];
        default:
            OWSFail(@"%@ Unexpected jumbomoji count: %zd", self.logTag, self.displayableText.jumbomojiCount);
            break;
    }

    return [UIFont ows_dynamicTypeBodyFont];
}

- (UIFont *)tapForMoreFont
{
    return [UIFont ows_regularFontWithSize:12.f];
}

- (CGFloat)tapForMoreHeight
{
    return (CGFloat)ceil([self tapForMoreFont].lineHeight * 1.25);
}

- (BOOL)shouldHaveFailedSendBadge
{
    if (![self.viewItem.interaction isKindOfClass:[TSOutgoingMessage class]]) {
        return NO;
    }
    TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
    return outgoingMessage.messageState == TSOutgoingMessageStateUnsent;
}

- (UIImage *)failedSendBadge
{
    UIImage *image = [UIImage imageNamed:@"message_send_failure"];
    OWSAssert(image);
    OWSAssert(image.size.width == self.failedSendBadgeSize && image.size.height == self.failedSendBadgeSize);
    return image;
}

- (CGFloat)failedSendBadgeSize
{
    return 20.f;
}

- (OWSMessageCellType)cellType
{
    return self.viewItem.messageCellType;
}

- (BOOL)hasText
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem);

    return self.viewItem.hasText;
}

- (nullable DisplayableText *)displayableText
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem.displayableText);

    return self.viewItem.displayableText;
}

- (nullable TSAttachmentStream *)attachmentStream
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem.attachmentStream);

    return self.viewItem.attachmentStream;
}

- (nullable TSAttachmentPointer *)attachmentPointer
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem.attachmentPointer);

    return self.viewItem.attachmentPointer;
}

- (CGSize)mediaSize
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem.mediaSize.width > 0 && self.viewItem.mediaSize.height > 0);

    return self.viewItem.mediaSize;
}

- (TSMessage *)message
{
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    return (TSMessage *)self.viewItem.interaction;
}

- (BOOL)hasNonImageBodyContent
{
    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
        case OWSMessageCellType_GenericAttachment:
        case OWSMessageCellType_DownloadingAttachment:
            return YES;
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_Video:
            return self.hasText;
    }
}

- (BOOL)hasBodyTextContent
{
    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            return YES;
        case OWSMessageCellType_GenericAttachment:
        case OWSMessageCellType_DownloadingAttachment:
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_Video:
            // Is there a caption?
            return self.hasText;
    }
}

#pragma mark - Load

- (void)loadForDisplay
{
    OWSAssert(self.viewItem);
    OWSAssert(self.viewItem.interaction);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    if (self.shouldHaveFailedSendBadge) {
        self.failedSendBadgeView = [UIImageView new];
        self.failedSendBadgeView.image =
            [self.failedSendBadge imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.failedSendBadgeView.tintColor = [UIColor ows_destructiveRedColor];
        [self.contentView addSubview:self.failedSendBadgeView];

        self.cellContentConstraints = @[
            [self.bubbleView autoPinLeadingToSuperview],
            [self.failedSendBadgeView autoPinLeadingToTrailingOfView:self.bubbleView],
            [self.failedSendBadgeView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.bubbleView],
            //                                    [self.payloadView autoPinLeadingToSuperview],
            //            [self.failedSendBadgeView autoPinLeadingToTrailingOfView:self.payloadView],
            [self.failedSendBadgeView autoPinTrailingToSuperview],
            //            [self.failedSendBadgeView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.payloadView],
            [self.failedSendBadgeView autoSetDimension:ALDimensionWidth toSize:self.failedSendBadgeSize],
            [self.failedSendBadgeView autoSetDimension:ALDimensionHeight toSize:self.failedSendBadgeSize],
        ];
    } else {
        self.cellContentConstraints = @[
            [self.bubbleView autoPinLeadingToSuperview],
            [self.bubbleView autoPinTrailingToSuperview],
            //                            [self.bubbleView autoPinLeadingToSuperview],
            //                                        [self.bubbleView autoPinWidthToSuperview],
        ];
        //        self.cellContentConstraints = [self.payloadView autoPinWidthToSuperview];
    }

    //    JSQMessagesBubbleImage *_Nullable bubbleImageData;
    if ([self.viewItem.interaction isKindOfClass:[TSMessage class]] && self.hasNonImageBodyContent) {
        TSMessage *message = (TSMessage *)self.viewItem.interaction;
        //        bubbleImageData = [self.bubbleFactory bubbleWithMessage:message];
        // TODO:
        self.bubbleView.bubbleColor = [self.bubbleFactory bubbleColorWithMessage:message];
        //        self.bubbleFillView.bubbleColor = [self.bubbleFactory bubbleColorWithMessage:message];
    } else {
        OWSFail(@"%@ Unknown interaction type: %@", self.logTag, self.viewItem.interaction.class);
    }

    //<<<<<<< HEAD
    //    self.textBubbleImageView.image = bubbleImageData.messageBubbleImage;
    //||||||| merged common ancestors
    //    self.bubbleImageView.image = bubbleImageData.messageBubbleImage;
    //=======
    //    // TODO:
    ////    self.bubbleImageView.image = bubbleImageData.messageBubbleImage;
    //    self.bubbleFillView.isOutgoing = self.isOutgoing;
    //>>>>>>> SQUASHED

    [self updateDateHeader];
    [self updateFooter];

    //    NSMutableArray<UIView *> *contentViews = [NSMutableArray new];
    //
    //    switch (self.cellType) {
    //        case OWSMessageCellType_Unknown:
    //            OWSFail(@"Unknown cell type for viewItem: %@", self.viewItem);
    //            break;
    //        case OWSMessageCellType_TextMessage:
    //            [self loadForTextDisplay];
    //            break;
    //        case OWSMessageCellType_OversizeTextMessage:
    //            OWSAssert(self.viewItem.attachmentStream);
    //            [self loadForTextDisplay];
    //            break;
    //        case OWSMessageCellType_StillImage:
    //            OWSAssert(self.viewItem.attachmentStream);
    //            [self loadForStillImageDisplay];
    //            break;
    //        case OWSMessageCellType_AnimatedImage:
    //            OWSAssert(self.viewItem.attachmentStream);
    //            [self loadForAnimatedImageDisplay];
    //            break;
    //        case OWSMessageCellType_Audio:
    //            OWSAssert(self.viewItem.attachmentStream);
    //            [self loadForAudioDisplay];
    //            break;
    //        case OWSMessageCellType_Video:
    //            OWSAssert(self.viewItem.attachmentStream);
    //            [self loadForVideoDisplay];
    //            break;
    //        case OWSMessageCellType_GenericAttachment: {
    //            OWSAssert(self.viewItem.attachmentStream);
    //            OWSGenericAttachmentView *attachmentView =
    //                [[OWSGenericAttachmentView alloc] initWithAttachment:self.attachmentStream
    //                isIncoming:self.isIncoming];
    //            [attachmentView createContents];
    //            [self setMediaView:attachmentView];
    //            [self addAttachmentUploadViewIfNecessary:attachmentView];
    //            [self addCaptionIfNecessary];
    //            break;
    //        }
    //        case OWSMessageCellType_DownloadingAttachment: {
    //            [self loadForDownloadingAttachment];
    //            [self addCaptionIfNecessary];
    //            break;
    //        }
    //    }

    //                                                       [self.tapForMoreLabel
    //                                                       autoPinLeadingToSuperviewWithMargin:self.textLeadingMargin],
    //                                                       [self.tapForMoreLabel
    //                                                       autoPinTrailingToSuperviewWithMargin:self.textTrailingMargin],
    //                                                       [self.tapForMoreLabel autoPinEdge:ALEdgeTop
    //                                                       toEdge:ALEdgeBottom ofView:self.textView],
    //                                                       [self.tapForMoreLabel
    //                                                       autoPinEdgeToSuperviewEdge:ALEdgeBottom
    //                                                       withInset:self.textBottomMargin], [self.tapForMoreLabel
    //                                                       autoSetDimension:ALDimensionHeight
    //                                                       toSize:self.tapForMoreHeight],


    // Do we need to pin the bubble size?
    {
        //        - (CGSize)cellSizeForViewWidth:(int)viewWidth contentWidth:(int)contentWidth
        //    CGSize mediaSize = [self bodyMediaSizeForContentWidth:self.contentWidth];
        // TODO:
        //    [self.bubbleContentConstraints addObjectsFromArray:[self.mediaMaskingView
        //    autoSetDimensionsToSize:mediaSize]];
    }

    UIView *_Nullable lastSubview = nil;
    CGFloat bottomMargin = 0;
    //    for (UIView *subview in contentViews) {
    //        [self.bubbleView addSubview:subview];
    //        if (last
    //        lastSubview = subview;
    //    }

    UIView *_Nullable bodyMediaView = nil;
    BOOL bodyMediaViewHasGreedyWidth = NO;
    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            break;
        case OWSMessageCellType_StillImage:
            OWSAssert(self.viewItem.attachmentStream);
            bodyMediaView = [self loadViewForStillImage];
            break;
        case OWSMessageCellType_AnimatedImage:
            OWSAssert(self.viewItem.attachmentStream);
            bodyMediaView = [self loadViewForAnimatedImage];
            break;
        case OWSMessageCellType_Video:
            OWSAssert(self.viewItem.attachmentStream);
            bodyMediaView = [self loadViewForVideo];
            break;
        case OWSMessageCellType_Audio:
            OWSAssert(self.viewItem.attachmentStream);
            bodyMediaView = [self loadViewForAudio];
            bodyMediaViewHasGreedyWidth = YES;
            break;
        case OWSMessageCellType_GenericAttachment:
            bodyMediaView = [self loadViewForGenericAttachment];
            bodyMediaViewHasGreedyWidth = YES;
            break;
        case OWSMessageCellType_DownloadingAttachment:
            bodyMediaView = [self loadViewForDownloadingAttachment];
            bodyMediaViewHasGreedyWidth = YES;
            break;
    }

    if (bodyMediaView) {
        OWSAssert(self.loadCellContentBlock);
        OWSAssert(self.unloadCellContentBlock);
        OWSAssert(!lastSubview);

        bodyMediaView.userInteractionEnabled = NO;
        if (self.isMediaBeingSent) {
            bodyMediaView.layer.opacity = 0.75f;
        }

        // TODO: Is this right?
        CGFloat contentWidth = self.width;
        // Sometimes we want the media to "try to fill" the message bubble.
        // For example, when the message bubble contains just an image, we
        // want the image's bounds to exactly fill the message bubble.
        //
        // In other situations, we want to center the media within the message
        // bubble.
        // For example, when a message has a tall portrait image and a long
        // caption.
        CGSize bodyMediaSize = [self bodyMediaSizeForContentWidth:(int)contentWidth];
        BOOL hasValidMediaSize = bodyMediaSize.width > 0.01 && bodyMediaSize.height > 0.01;
        if (!hasValidMediaSize) {
            bodyMediaViewHasGreedyWidth = YES;
        } else if (!self.hasText) {
            bodyMediaViewHasGreedyWidth = YES;
        }

        [self.bubbleView addSubview:bodyMediaView];
        if (bodyMediaViewHasGreedyWidth) {
            [self.bubbleContentConstraints addObjectsFromArray:@[
                [bodyMediaView autoPinLeadingToSuperviewWithMargin:0],
                [bodyMediaView autoPinTrailingToSuperviewWithMargin:0],
            ]];
        } else {
            CGFloat aspectRatio = bodyMediaSize.width / bodyMediaSize.height;
            [self.bubbleContentConstraints addObjectsFromArray:@[
                [bodyMediaView autoHCenterInSuperview],
                [bodyMediaView autoPinToAspectRatio:aspectRatio],
            ]];
        }
        if (lastSubview) {
            [self.bubbleContentConstraints
                addObject:[bodyMediaView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:lastSubview withOffset:0]];
        } else {
            [self.bubbleContentConstraints addObject:[bodyMediaView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:0]];
        }
        lastSubview = bodyMediaView;
        bottomMargin = 0;
    }

    UIView *_Nullable bodyTextView = nil;
    // We render malformed messages as "empty text" messages,
    // so create a text view if there is no body media view.
    if (self.hasText || !bodyMediaView) {
        bodyTextView = [self createBodyTextViewIfNecessary];
    }
    if (bodyTextView) {
        [self.bubbleView addSubview:bodyTextView];
        [self.bubbleContentConstraints addObjectsFromArray:@[
            [bodyTextView autoPinLeadingToSuperviewWithMargin:self.textLeadingMargin],
            [bodyTextView autoPinTrailingToSuperviewWithMargin:self.textTrailingMargin],
        ]];
        if (lastSubview) {
            [self.bubbleContentConstraints addObject:[bodyTextView autoPinEdge:ALEdgeTop
                                                                        toEdge:ALEdgeBottom
                                                                        ofView:lastSubview
                                                                    withOffset:self.textTopMargin]];
        } else {
            [self.bubbleContentConstraints
                addObject:[bodyTextView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:self.textTopMargin]];
        }
        lastSubview = bodyTextView;
        bottomMargin = self.textBottomMargin;
    }

    UIView *_Nullable tapForMoreLabel = [self createTapForMoreLabelIfNecessary];
    if (tapForMoreLabel) {
        OWSAssert(lastSubview);
        OWSAssert(lastSubview == bodyTextView);
        [self.bubbleView addSubview:tapForMoreLabel];
        [self.bubbleContentConstraints addObjectsFromArray:@[
            [tapForMoreLabel autoPinLeadingToSuperviewWithMargin:self.textLeadingMargin],
            [tapForMoreLabel autoPinTrailingToSuperviewWithMargin:self.textTrailingMargin],
            [tapForMoreLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:lastSubview],
            [tapForMoreLabel autoSetDimension:ALDimensionHeight toSize:self.tapForMoreHeight],
        ]];
        lastSubview = tapForMoreLabel;
        bottomMargin = self.textBottomMargin;
    }

    OWSAssert(lastSubview);
    [self.bubbleContentConstraints addObjectsFromArray:@[
        [lastSubview autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:bottomMargin],
    ]];

    [self ensureMediaLoadState];
}

// We now eagerly create our view hierarchy (to do this exactly once per cell usage)
// but lazy-load any expensive media (photo, gif, etc.) used in those views. Note that
// this lazy-load can fail, in which case we modify the view hierarchy to use an "error"
// state. The didCellMediaFailToLoad reflects media load fails.
- (nullable id)tryToLoadCellMedia:(nullable id (^)(void))loadCellMediaBlock
                        mediaView:(UIView *)mediaView
                         cacheKey:(NSString *)cacheKey
{
    OWSAssert(self.attachmentStream);
    OWSAssert(mediaView);
    OWSAssert(cacheKey);

    if (self.viewItem.didCellMediaFailToLoad) {
        return nil;
    }

    NSCache *cellMediaCache = self.delegate.cellMediaCache;
    OWSAssert(cellMediaCache);

    id _Nullable cellMedia = [cellMediaCache objectForKey:cacheKey];
    if (cellMedia) {
        DDLogVerbose(@"%@ cell media cache hit", self.logTag);
        return cellMedia;
    }
    cellMedia = loadCellMediaBlock();
    if (cellMedia) {
        DDLogVerbose(@"%@ cell media cache miss", self.logTag);
        [cellMediaCache setObject:cellMedia forKey:cacheKey];
    } else {
        DDLogError(@"%@ Failed to load cell media: %@", [self logTag], [self.attachmentStream mediaURL]);
        self.viewItem.didCellMediaFailToLoad = YES;
        [mediaView removeFromSuperview];
        // TODO: We need to hide/remove the media view.
        [self showAttachmentErrorView:mediaView];
    }
    return cellMedia;
}

// * If cell is visible, lazy-load (expensive) view contents.
// * If cell is not visible, eagerly unload view contents.
- (void)ensureMediaLoadState
{
    //    CGSize mediaSize = [self bodyMediaSizeForContentWidth:self.contentWidth];
    // TODO:
    //    [self.bubbleContentConstraints addObjectsFromArray:[self.mediaMaskingView autoSetDimensionsToSize:mediaSize]];

    if (!self.isCellVisible) {
        // Eagerly unload.
        if (self.unloadCellContentBlock) {
            self.unloadCellContentBlock();
        }
        return;
    } else {
        // Lazy load.
        if (self.loadCellContentBlock) {
            self.loadCellContentBlock();
        }
    }

    //    switch (self.cellType) {
    //        case OWSMessageCellType_StillImage: {
    //            if (self.stillImageView.image) {
    //                return;
    //            }
    //            self.stillImageView.image = [self tryToLoadCellMedia:^{
    //                OWSAssert([self.attachmentStream isImage]);
    //                return self.attachmentStream.image;
    //            }
    //                                                       mediaView:self.stillImageView
    //                                                        cacheKey:self.attachmentStream.uniqueId];
    //            break;
    //        }
    //        case OWSMessageCellType_AnimatedImage: {
    //            if (self.animatedImageView.image) {
    //                return;
    //            }
    //            self.animatedImageView.image = [self tryToLoadCellMedia:^{
    //                OWSAssert([self.attachmentStream isAnimated]);
    //
    //                NSString *_Nullable filePath = [self.attachmentStream filePath];
    //                YYImage *_Nullable animatedImage = nil;
    //                if (filePath && [NSData ows_isValidImageAtPath:filePath]) {
    //                    animatedImage = [YYImage imageWithContentsOfFile:filePath];
    //                }
    //                return animatedImage;
    //            }
    //                                                          mediaView:self.animatedImageView
    //                                                           cacheKey:self.attachmentStream.uniqueId];
    //            break;
    //        }
    //        case OWSMessageCellType_Video: {
    //            if (self.stillImageView.image) {
    //                return;
    //            }
    //            self.stillImageView.image = [self tryToLoadCellMedia:^{
    //                OWSAssert([self.attachmentStream isVideo]);
    //
    //                return self.attachmentStream.image;
    //            }
    //                                                       mediaView:self.stillImageView
    //                                                        cacheKey:self.attachmentStream.uniqueId];
    //            break;
    //        }
    //        case OWSMessageCellType_TextMessage:
    //        case OWSMessageCellType_OversizeTextMessage:
    //        case OWSMessageCellType_GenericAttachment:
    //        case OWSMessageCellType_DownloadingAttachment:
    //        case OWSMessageCellType_Audio:
    //        case OWSMessageCellType_Unknown:
    //            // Inexpensive cell types don't need to lazy-load or eagerly-unload.
    //            break;
    //    }
}

- (void)updateDateHeader
{
    OWSAssert(self.contentWidth > 0);

    static NSDateFormatter *dateHeaderDateFormatter = nil;
    static NSDateFormatter *dateHeaderTimeFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateHeaderDateFormatter = [NSDateFormatter new];
        [dateHeaderDateFormatter setLocale:[NSLocale currentLocale]];
        [dateHeaderDateFormatter setDoesRelativeDateFormatting:YES];
        [dateHeaderDateFormatter setDateStyle:NSDateFormatterMediumStyle];
        [dateHeaderDateFormatter setTimeStyle:NSDateFormatterNoStyle];
        
        dateHeaderTimeFormatter = [NSDateFormatter new];
        [dateHeaderTimeFormatter setLocale:[NSLocale currentLocale]];
        [dateHeaderTimeFormatter setDoesRelativeDateFormatting:YES];
        [dateHeaderTimeFormatter setDateStyle:NSDateFormatterNoStyle];
        [dateHeaderTimeFormatter setTimeStyle:NSDateFormatterShortStyle];
    });

    if (self.viewItem.shouldShowDate) {
        NSDate *date = self.viewItem.interaction.dateForSorting;
        NSString *dateString = [dateHeaderDateFormatter stringFromDate:date];
        NSString *timeString = [dateHeaderTimeFormatter stringFromDate:date];

        NSAttributedString *attributedText = [NSAttributedString new];
        attributedText = [attributedText rtlSafeAppend:dateString
                                            attributes:@{
                                                NSFontAttributeName : self.dateHeaderDateFont,
                                                NSForegroundColorAttributeName : [UIColor lightGrayColor],
                                            }
                                         referenceView:self];
        attributedText = [attributedText rtlSafeAppend:@" "
                                            attributes:@{
                                                NSFontAttributeName : self.dateHeaderDateFont,
                                            }
                                         referenceView:self];
        attributedText = [attributedText rtlSafeAppend:timeString
                                            attributes:@{
                                                NSFontAttributeName : self.dateHeaderTimeFont,
                                                NSForegroundColorAttributeName : [UIColor lightGrayColor],
                                            }
                                         referenceView:self];

        self.dateHeaderLabel.attributedText = attributedText;
        self.dateHeaderLabel.hidden = NO;

        self.dateHeaderConstraints = @[
            // Date headers should be visually centered within the conversation view,
            // so they need to extend outside the cell's boundaries.
            [self.dateHeaderLabel autoSetDimension:ALDimensionWidth toSize:self.contentWidth],
            (self.isIncoming ? [self.dateHeaderLabel autoPinEdgeToSuperviewEdge:ALEdgeLeading]
                             : [self.dateHeaderLabel autoPinEdgeToSuperviewEdge:ALEdgeTrailing]),
            [self.dateHeaderLabel autoPinEdgeToSuperviewEdge:ALEdgeTop],
            [self.dateHeaderLabel autoSetDimension:ALDimensionHeight toSize:self.dateHeaderHeight],
        ];
    } else {
        self.dateHeaderLabel.hidden = YES;
        self.dateHeaderConstraints = @[
            [self.dateHeaderLabel autoSetDimension:ALDimensionHeight toSize:0],
            [self.dateHeaderLabel autoPinEdgeToSuperviewEdge:ALEdgeTop],
        ];
    }
}

- (CGFloat)footerHeight
{
    BOOL showFooter = NO;

    BOOL hasExpirationTimer = self.message.shouldStartExpireTimer;

    if (hasExpirationTimer) {
        showFooter = YES;
    } else if (self.isOutgoing) {
        showFooter = !self.viewItem.shouldHideRecipientStatus;
    } else if (self.viewItem.isGroupThread) {
        showFooter = YES;
    } else {
        showFooter = NO;
    }

    return (showFooter ? MAX(kExpirationTimerViewSize,
                             self.footerLabel.font.lineHeight)
            : 0.f);
}

- (void)updateFooter
{
    OWSAssert(self.viewItem.interaction.interactionType == OWSInteractionType_IncomingMessage
        || self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage);

    TSMessage *message = self.message;
    BOOL hasExpirationTimer = message.shouldStartExpireTimer;
    NSAttributedString *attributedText = nil;
    if (self.isOutgoing) {
        if (!self.viewItem.shouldHideRecipientStatus || hasExpirationTimer) {
            TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)message;
            NSString *statusMessage =
                [MessageRecipientStatusUtils statusMessageWithOutgoingMessage:outgoingMessage referenceView:self];
            attributedText = [[NSAttributedString alloc] initWithString:statusMessage attributes:@{}];
        }
    } else if (self.viewItem.isGroupThread) {
        TSIncomingMessage *incomingMessage = (TSIncomingMessage *)self.viewItem.interaction;
        attributedText = [self.delegate attributedContactOrProfileNameForPhoneIdentifier:incomingMessage.authorId];
    }
    
    if (!hasExpirationTimer &&
        !attributedText) {
        self.footerLabel.hidden = YES;
        self.footerConstraints = @[
                                   [self.footerView autoSetDimension:ALDimensionHeight toSize:0],
                                   ];
        return;
    }

    if (hasExpirationTimer) {
        uint64_t expirationTimestamp = message.expiresAt;
        uint32_t expiresInSeconds = message.expiresInSeconds;
        self.expirationTimerView = [[OWSExpirationTimerView alloc] initWithExpiration:expirationTimestamp
                                                               initialDurationSeconds:expiresInSeconds];
        [self.footerView addSubview:self.expirationTimerView];
    }
    if (attributedText) {
        self.footerLabel.attributedText = attributedText;
        self.footerLabel.hidden = NO;
    }

    if (hasExpirationTimer &&
        attributedText) {
        self.footerConstraints = @[
                                   [self.expirationTimerView autoVCenterInSuperview],
                                   [self.footerLabel autoVCenterInSuperview],
                                   (self.isIncoming
                                    ? [self.expirationTimerView autoPinLeadingToSuperview]
                                    : [self.expirationTimerView autoPinTrailingToSuperview]),
                                   (self.isIncoming
                                    ? [self.footerLabel autoPinLeadingToTrailingOfView:self.expirationTimerView margin:0.f]
                                    : [self.footerLabel autoPinTrailingToLeadingOfView:self.expirationTimerView margin:0.f]),
                                   [self.footerView autoSetDimension:ALDimensionHeight toSize:self.footerHeight],
                                   ];
    } else if (hasExpirationTimer) {
        self.footerConstraints = @[
                                   [self.expirationTimerView autoVCenterInSuperview],
                                   (self.isIncoming
                                    ? [self.expirationTimerView autoPinLeadingToSuperview]
                                    : [self.expirationTimerView autoPinTrailingToSuperview]),
                                   [self.footerView autoSetDimension:ALDimensionHeight toSize:self.footerHeight],
                                   ];
    } else if (attributedText) {
        self.footerConstraints = @[
                                   [self.footerLabel autoVCenterInSuperview],
                                   (self.isIncoming
                                    ? [self.footerLabel autoPinLeadingToSuperview]
                                    : [self.footerLabel autoPinTrailingToSuperview]),
                                   [self.footerView autoSetDimension:ALDimensionHeight toSize:self.footerHeight],
                                   ];
    } else {
        OWSFail(@"%@ Cell unexpectedly has neither expiration timer nor footer text.", self.logTag);
    }
}

- (UIFont *)dateHeaderDateFont
{
    return [UIFont boldSystemFontOfSize:12.0f];
}

- (UIFont *)dateHeaderTimeFont
{
    return [UIFont systemFontOfSize:12.0f];
}

- (OWSMessageTextView *)createBodyTextViewIfNecessary
{
    BOOL shouldIgnoreEvents = NO;
    if (self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        // Ignore taps on links in outgoing messages that haven't been sent yet, as
        // this interferes with "tap to retry".
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
        shouldIgnoreEvents = outgoingMessage.messageState != TSOutgoingMessageStateSentToService;
    }
    [self.class loadForTextDisplay:self.bodyTextViewCached
                              text:self.displayableText.displayText
                         textColor:self.textColor
                              font:self.textMessageFont
                shouldIgnoreEvents:shouldIgnoreEvents];
    return self.bodyTextViewCached;
}

+ (void)loadForTextDisplay:(OWSMessageTextView *)textView
                      text:(NSString *)text
                 textColor:(UIColor *)textColor
                      font:(UIFont *)font
        shouldIgnoreEvents:(BOOL)shouldIgnoreEvents
{
    //<<<<<<< HEAD
    //    self.textBubbleImageView.hidden = NO;
    //||||||| merged common ancestors
    //    self.bubbleImageView.hidden = NO;
    //=======
    //    self.bubbleFillView.hidden = NO;
    ////    self.bubbleImageView.hidden = NO;
    //>>>>>>> SQUASHED
    textView.hidden = NO;
    textView.text = text;
    textView.textColor = textColor;

    // Honor dynamic type in the message bodies.
    textView.font = font;
    textView.linkTextAttributes = @{
        NSForegroundColorAttributeName : textColor,
        NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid)
    };
    textView.dataDetectorTypes = (UIDataDetectorTypeLink | UIDataDetectorTypeAddress | UIDataDetectorTypeCalendarEvent);
    textView.shouldIgnoreEvents = shouldIgnoreEvents;

    //        OWSAssert(self.contentWidth);
    //        CGSize textBubbleSize = [self textBubbleSizeForContentWidth:self.contentWidth];
    //
    //        if (self.displayableText.isTextTruncated) {
    //            self.tapForMoreLabel = [UILabel new];
    //            self.tapForMoreLabel.text = NSLocalizedString(@"CONVERSATION_VIEW_OVERSIZE_TEXT_TAP_FOR_MORE",
    //                                                          @"Indicator on truncated text messages that they can be
    //                                                          tapped to see the entire text message.");
    //            self.tapForMoreLabel.font = [self tapForMoreFont];
    //            self.tapForMoreLabel.textColor = [self.textColor colorWithAlphaComponent:0.85];
    //            self.tapForMoreLabel.textAlignment = [self.tapForMoreLabel textAlignmentUnnatural];
    //            <<<<<<< HEAD
    //            [self.textBubbleImageView addSubview:self.tapForMoreLabel];
    //            ||||||| merged common ancestors
    //            [self.bubbleImageView addSubview:self.tapForMoreLabel];
    //            =======
    //            [self.bubbleFillView addSubview:self.tapForMoreLabel];
    //            >>>>>>> SQUASHED
    //
    //            [self.bubbleContentConstraints addObjectsFromArray:@[
    //                                                           [self.textBubbleImageView
    //                                                           autoSetDimension:ALDimensionWidth
    //                                                           toSize:textBubbleSize.width], [self.textBubbleImageView
    //                                                           autoSetDimension:ALDimensionHeight
    //                                                           toSize:textBubbleSize.height], [self.textView
    //                                                           autoPinLeadingToSuperviewWithMargin:self.textLeadingMargin],
    //                                                           [self.textView
    //                                                           autoPinTrailingToSuperviewWithMargin:self.textTrailingMargin],
    //                                                           [self.textView autoPinEdgeToSuperviewEdge:ALEdgeTop
    //                                                           withInset:self.textTopMargin],
    //
    //                                                           [self.tapForMoreLabel
    //                                                           autoPinLeadingToSuperviewWithMargin:self.textLeadingMargin],
    //                                                           [self.tapForMoreLabel
    //                                                           autoPinTrailingToSuperviewWithMargin:self.textTrailingMargin],
    //                                                           [self.tapForMoreLabel autoPinEdge:ALEdgeTop
    //                                                           toEdge:ALEdgeBottom ofView:self.textView],
    //                                                           [self.tapForMoreLabel
    //                                                           autoPinEdgeToSuperviewEdge:ALEdgeBottom
    //                                                           withInset:self.textBottomMargin], [self.tapForMoreLabel
    //                                                           autoSetDimension:ALDimensionHeight
    //                                                           toSize:self.tapForMoreHeight],
    //                                                           ]];
    //        } else {
    //            [self.bubbleContentConstraints addObjectsFromArray:@[
    //                                                           [self.textBubbleImageView
    //                                                           autoSetDimension:ALDimensionWidth
    //                                                           toSize:textBubbleSize.width], [self.textBubbleImageView
    //                                                           autoSetDimension:ALDimensionHeight
    //                                                           toSize:textBubbleSize.height],
    //                                                           [self.textBubbleImageView
    //                                                           autoPinEdgeToSuperviewEdge:(self.isIncoming ?
    //                                                           ALEdgeLeading : ALEdgeTrailing)], [self.textView
    //                                                           autoPinLeadingToSuperviewWithMargin:self.textLeadingMargin],
    //                                                           [self.textView
    //                                                           autoPinTrailingToSuperviewWithMargin:self.textTrailingMargin],
    //                                                           <<<<<<< HEAD
    //                                                           [self.textView autoPinEdgeToSuperviewEdge:ALEdgeTop
    //                                                           withInset:self.textVMargin], [self.textView
    //                                                           autoPinEdgeToSuperviewEdge:ALEdgeBottom
    //                                                           withInset:self.textVMargin],
    //                                                           ]];
    //            ||||||| merged common ancestors
    //            [self.textView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:self.textVMargin],
    //            [self.textView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:self.textVMargin],
    //            ];
    //            =======
    //            [self.textView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:self.textTopMargin],
    //            [self.textView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:self.textBottomMargin],
    //            ];
    //            >>>>>>> SQUASHED
    //        }
}

- (nullable UIView *)createTapForMoreLabelIfNecessary
{
    //        //<<<<<<< HEAD
    //        //    self.textBubbleImageView.hidden = NO;
    //        //||||||| merged common ancestors
    //        //    self.bubbleImageView.hidden = NO;
    //        //=======
    //        //    self.bubbleFillView.hidden = NO;
    //        ////    self.bubbleImageView.hidden = NO;
    //        //>>>>>>> SQUASHED
    //        textView.hidden = NO;
    //        textView.text = text;
    //        textView.textColor = textColor;
    //
    //        // Honor dynamic type in the message bodies.
    //        textView.font = font;
    //        textView.linkTextAttributes = @{
    //                                        NSForegroundColorAttributeName : textColor,
    //                                        NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle |
    //                                        NSUnderlinePatternSolid)
    //                                        };
    //        textView.dataDetectorTypes
    //        = (UIDataDetectorTypeLink | UIDataDetectorTypeAddress | UIDataDetectorTypeCalendarEvent);
    //
    //        if (self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
    //            // Ignore taps on links in outgoing messages that haven't been sent yet, as
    //            // this interferes with "tap to retry".
    //            TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
    //            self.textView.shouldIgnoreEvents = outgoingMessage.messageState !=
    //            TSOutgoingMessageStateSentToService;
    //        } else {
    //            self.textView.shouldIgnoreEvents = NO;
    //        }
    //
    //        OWSAssert(self.contentWidth);
    //        CGSize textBubbleSize = [self textBubbleSizeForContentWidth:self.contentWidth];

    if (!self.hasText) {
        return nil;
    }
    if (!self.displayableText.isTextTruncated) {
        return nil;
    }

    UILabel *tapForMoreLabel = [UILabel new];
    tapForMoreLabel.text = NSLocalizedString(@"CONVERSATION_VIEW_OVERSIZE_TEXT_TAP_FOR_MORE",
        @"Indicator on truncated text messages that they can be tapped to see the entire text message.");
    tapForMoreLabel.font = [self tapForMoreFont];
    tapForMoreLabel.textColor = [self.textColor colorWithAlphaComponent:0.85];
    tapForMoreLabel.textAlignment = [tapForMoreLabel textAlignmentUnnatural];
    //        <<<<<<< HEAD
    //        [self.textBubbleImageView addSubview:self.tapForMoreLabel];
    //        ||||||| merged common ancestors
    //        [self.bubbleImageView addSubview:self.tapForMoreLabel];
    //        =======
    //        [self.bubbleFillView addSubview:self.tapForMoreLabel];
    //        >>>>>>> SQUASHED
    //
    //        [self.bubbleContentConstraints addObjectsFromArray:@[
    //                                                       [self.textBubbleImageView autoSetDimension:ALDimensionWidth
    //                                                       toSize:textBubbleSize.width], [self.textBubbleImageView
    //                                                       autoSetDimension:ALDimensionHeight
    //                                                       toSize:textBubbleSize.height], [self.textView
    //                                                       autoPinLeadingToSuperviewWithMargin:self.textLeadingMargin],
    //                                                       [self.textView
    //                                                       autoPinTrailingToSuperviewWithMargin:self.textTrailingMargin],
    //                                                       [self.textView autoPinEdgeToSuperviewEdge:ALEdgeTop
    //                                                       withInset:self.textTopMargin],
    //
    //                                                       [self.tapForMoreLabel
    //                                                       autoPinLeadingToSuperviewWithMargin:self.textLeadingMargin],
    //                                                       [self.tapForMoreLabel
    //                                                       autoPinTrailingToSuperviewWithMargin:self.textTrailingMargin],
    //                                                       [self.tapForMoreLabel autoPinEdge:ALEdgeTop
    //                                                       toEdge:ALEdgeBottom ofView:self.textView],
    //                                                       [self.tapForMoreLabel
    //                                                       autoPinEdgeToSuperviewEdge:ALEdgeBottom
    //                                                       withInset:self.textBottomMargin], [self.tapForMoreLabel
    //                                                       autoSetDimension:ALDimensionHeight
    //                                                       toSize:self.tapForMoreHeight],
    //                                                       ]];
    //    } else {
    //        [self.bubbleContentConstraints addObjectsFromArray:@[
    //                                                       [self.textBubbleImageView autoSetDimension:ALDimensionWidth
    //                                                       toSize:textBubbleSize.width], [self.textBubbleImageView
    //                                                       autoSetDimension:ALDimensionHeight
    //                                                       toSize:textBubbleSize.height], [self.textBubbleImageView
    //                                                       autoPinEdgeToSuperviewEdge:(self.isIncoming ? ALEdgeLeading
    //                                                       : ALEdgeTrailing)], [self.textView
    //                                                       autoPinLeadingToSuperviewWithMargin:self.textLeadingMargin],
    //                                                       [self.textView
    //                                                       autoPinTrailingToSuperviewWithMargin:self.textTrailingMargin],
    //                                                       <<<<<<< HEAD
    //                                                       [self.textView autoPinEdgeToSuperviewEdge:ALEdgeTop
    //                                                       withInset:self.textVMargin], [self.textView
    //                                                       autoPinEdgeToSuperviewEdge:ALEdgeBottom
    //                                                       withInset:self.textVMargin],
    //                                                       ]];
    //        ||||||| merged common ancestors
    //        [self.textView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:self.textVMargin],
    //        [self.textView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:self.textVMargin],
    //        ];
    //        =======
    //        [self.textView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:self.textTopMargin],
    //        [self.textView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:self.textBottomMargin],
    //        ];
    //        >>>>>>> SQUASHED
    //    }

    return tapForMoreLabel;
}

- (UIView *)loadViewForStillImage
{
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isImage]);

    UIImageView *stillImageView = [UIImageView new];
    // We need to specify a contentMode since the size of the image
    // might not match the aspect ratio of the view.
    stillImageView.contentMode = UIViewContentModeScaleAspectFill;
    // Use trilinear filters for better scaling quality at
    // some performance cost.
    stillImageView.layer.minificationFilter = kCAFilterTrilinear;
    stillImageView.layer.magnificationFilter = kCAFilterTrilinear;
    //    [self setMediaView:self.stillImageView];
    [self addAttachmentUploadViewIfNecessary:stillImageView];
    //    [self addCaptionIfNecessary];

    __weak OWSMessageCell *weakSelf = self;
    self.loadCellContentBlock = ^{
        OWSMessageCell *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (stillImageView.image) {
            return;
        }
        stillImageView.image = [strongSelf tryToLoadCellMedia:^{
            OWSCAssert([strongSelf.attachmentStream isImage]);
            return strongSelf.attachmentStream.image;
        }
                                                    mediaView:stillImageView
                                                     cacheKey:strongSelf.attachmentStream.uniqueId];
    };
    self.unloadCellContentBlock = ^{
        stillImageView.image = nil;
    };
    self.lastImageView = stillImageView;

    return stillImageView;
}

- (UIView *)loadViewForAnimatedImage
{
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isAnimated]);

    YYAnimatedImageView *animatedImageView = [[YYAnimatedImageView alloc] init];
    // We need to specify a contentMode since the size of the image
    // might not match the aspect ratio of the view.
    animatedImageView.contentMode = UIViewContentModeScaleAspectFill;
    //    [self setMediaView:self.animatedImageView];
    [self addAttachmentUploadViewIfNecessary:animatedImageView];
    //    [self addCaptionIfNecessary];

    __weak OWSMessageCell *weakSelf = self;
    self.loadCellContentBlock = ^{
        OWSMessageCell *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (animatedImageView.image) {
            return;
        }
        animatedImageView.image = [strongSelf tryToLoadCellMedia:^{
            OWSCAssert([strongSelf.attachmentStream isAnimated]);

            NSString *_Nullable filePath = [strongSelf.attachmentStream filePath];
            YYImage *_Nullable animatedImage = nil;
            if (filePath && [NSData ows_isValidImageAtPath:filePath]) {
                animatedImage = [YYImage imageWithContentsOfFile:filePath];
            }
            return animatedImage;
        }
                                                       mediaView:animatedImageView
                                                        cacheKey:strongSelf.attachmentStream.uniqueId];
    };
    self.unloadCellContentBlock = ^{
        animatedImageView.image = nil;
    };
    self.lastImageView = animatedImageView;

    return animatedImageView;
}

//// TODO:
//- (void)addCaptionIfNecessary
//{
//    if (self.hasText) {
//        [self loadForTextDisplay];
//    } else {
//        [self.bubbleContentConstraints addObject:[self.textBubbleImageView autoSetDimension:ALDimensionHeight
//        toSize:0]];
//    }
//}

- (UIView *)loadViewForAudio
{
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isAudio]);

    OWSAudioMessageView *audioMessageView = [[OWSAudioMessageView alloc] initWithAttachment:self.attachmentStream
                                                                                 isIncoming:self.isIncoming
                                                                                   viewItem:self.viewItem];
    self.viewItem.lastAudioMessageView = audioMessageView;
    [audioMessageView createContents];
    //    [self setMediaView:self.audioMessageView];
    [self addAttachmentUploadViewIfNecessary:audioMessageView];
    //    [self addCaptionIfNecessary];

    self.loadCellContentBlock = ^{
        // Do nothing.
    };
    self.unloadCellContentBlock = ^{
        // Do nothing.
    };

    return audioMessageView;
}

- (UIView *)loadViewForVideo
{
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isVideo]);

    UIImageView *stillImageView = [UIImageView new];
    // We need to specify a contentMode since the size of the image
    // might not match the aspect ratio of the view.
    stillImageView.contentMode = UIViewContentModeScaleAspectFill;
    // Use trilinear filters for better scaling quality at
    // some performance cost.
    stillImageView.layer.minificationFilter = kCAFilterTrilinear;
    stillImageView.layer.magnificationFilter = kCAFilterTrilinear;
    //    [self setMediaView:stillImageView];

    UIImage *videoPlayIcon = [UIImage imageNamed:@"play_button"];
    UIImageView *videoPlayButton = [[UIImageView alloc] initWithImage:videoPlayIcon];
    [stillImageView addSubview:videoPlayButton];
    [videoPlayButton autoCenterInSuperview];
    [self addAttachmentUploadViewIfNecessary:stillImageView
                     attachmentStateCallback:^(BOOL isAttachmentReady) {
                         videoPlayButton.hidden = !isAttachmentReady;
                     }];
    //    [self addCaptionIfNecessary];

    __weak OWSMessageCell *weakSelf = self;
    self.loadCellContentBlock = ^{
        OWSMessageCell *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (stillImageView.image) {
            return;
        }
        stillImageView.image = [strongSelf tryToLoadCellMedia:^{
            OWSCAssert([strongSelf.attachmentStream isVideo]);

            return strongSelf.attachmentStream.image;
        }
                                                    mediaView:stillImageView
                                                     cacheKey:strongSelf.attachmentStream.uniqueId];
    };
    self.unloadCellContentBlock = ^{
        stillImageView.image = nil;
    };
    self.lastImageView = stillImageView;

    return stillImageView;
}

- (UIView *)loadViewForGenericAttachment
{
    OWSAssert(self.viewItem.attachmentStream);
    OWSGenericAttachmentView *attachmentView =
        [[OWSGenericAttachmentView alloc] initWithAttachment:self.attachmentStream isIncoming:self.isIncoming];
    [attachmentView createContents];
    //    [self setMediaView:attachmentView];
    [self addAttachmentUploadViewIfNecessary:attachmentView];
    //    [self addCaptionIfNecessary];

    self.loadCellContentBlock = ^{
        // Do nothing.
    };
    self.unloadCellContentBlock = ^{
        // Do nothing.
    };

    return attachmentView;
}

- (UIView *)loadViewForDownloadingAttachment
{
    OWSAssert(self.attachmentPointer);

    UIView *customView = [UIView new];
    switch (self.attachmentPointer.state) {
        case TSAttachmentPointerStateEnqueued:
            customView.backgroundColor
                = (self.isIncoming ? [UIColor jsq_messageBubbleLightGrayColor] : [UIColor ows_fadedBlueColor]);
            break;
        case TSAttachmentPointerStateDownloading:
            customView.backgroundColor
                = (self.isIncoming ? [UIColor jsq_messageBubbleLightGrayColor] : [UIColor ows_fadedBlueColor]);
            break;
        case TSAttachmentPointerStateFailed:
            customView.backgroundColor = [UIColor grayColor];
            break;
    }
    //    [self setMediaView:self.customView];

    AttachmentPointerView *attachmentPointerView =
        [[AttachmentPointerView alloc] initWithAttachmentPointer:self.attachmentPointer isIncoming:self.isIncoming];
    [customView addSubview:attachmentPointerView];
    [attachmentPointerView autoPinWidthToSuperviewWithMargin:20.f];
    [attachmentPointerView autoVCenterInSuperview];
    //    [self addCaptionIfNecessary];

    self.loadCellContentBlock = ^{
        // Do nothing.
    };
    self.unloadCellContentBlock = ^{
        // Do nothing.
    };

    return customView;
}

//- (void)setMediaView:(UIView *)view
//{
//    OWSAssert(view);
//
//    view.userInteractionEnabled = NO;
//    [self.mediaMaskingView addSubview:view];
//
//    [self.bubbleContentConstraints
//        addObject:[self.mediaMaskingView
//                      autoPinEdgeToSuperviewEdge:(self.isIncoming ? ALEdgeLeading : ALEdgeTrailing)]];
//
//    [self.bubbleContentConstraints addObjectsFromArray:[view autoPinEdgesToSuperviewMargins]];
//
//    [self cropMediaViewToBubbbleShape:view];
//    if (self.isMediaBeingSent) {
//        view.layer.opacity = 0.75f;
//    }
//}

- (void)addAttachmentUploadViewIfNecessary:(UIView *)attachmentView
{
    [self addAttachmentUploadViewIfNecessary:attachmentView
                     attachmentStateCallback:^(BOOL isAttachmentReady){
                     }];
}

- (void)addAttachmentUploadViewIfNecessary:(UIView *)attachmentView
                   attachmentStateCallback:(AttachmentStateBlock)attachmentStateCallback
{
    OWSAssert(attachmentView);
    OWSAssert(attachmentStateCallback);
    OWSAssert(self.attachmentStream);

    if (self.isOutgoing) {
        if (!self.attachmentStream.isUploaded) {
            __unused AttachmentUploadView *attachmentUploadView =
                //            self.attachmentUploadView =
                // This view will be added to attachmentView which will retain a strong reference to it.
                [[AttachmentUploadView alloc] initWithAttachment:self.attachmentStream
                                                       superview:attachmentView
                                         attachmentStateCallback:attachmentStateCallback];
        }
    }
}

//- (void)cropMediaViewToBubbbleShape:(UIView *)view
//{
//    OWSAssert(view);
//    OWSAssert(view.superview == self.mediaMaskingView);
//
//    self.mediaMaskingView.isOutgoing = self.isOutgoing;
//    // Hide tail on attachments followed by a caption
//    self.mediaMaskingView.hideTail = self.hasText;
//    self.mediaMaskingView.maskedSubview = view;
//    [self.mediaMaskingView updateMask];
//}

- (void)showAttachmentErrorView:(UIView *)mediaView
{
    OWSAssert(mediaView);

    // TODO: We could do a better job of indicating that the media could not be loaded.
    UIView *customView = [UIView new];
    customView.backgroundColor = [UIColor colorWithWhite:0.85f alpha:1.f];
    customView.userInteractionEnabled = NO;
    [mediaView addSubview:customView];
    [customView autoPinEdgesToSuperviewEdges];
}

#pragma mark - Measurement

// Size of "message body" text, not quoted reply text.
- (CGSize)bodyTextSizeForContentWidth:(int)contentWidth
{
    if (!self.hasText) {
        return CGSizeZero;
    }

    BOOL isRTL = self.isRTL;
    CGFloat leftMargin = isRTL ? self.textTrailingMargin : self.textLeadingMargin;
    CGFloat rightMargin = isRTL ? self.textLeadingMargin : self.textTrailingMargin;

    const int maxMessageWidth = [self maxMessageWidthForContentWidth:contentWidth];
    const int maxTextWidth = (int)floor(maxMessageWidth - (leftMargin + rightMargin));

    self.bodyTextViewCached.text = self.displayableText.displayText;
    // Honor dynamic type in the message bodies.
    self.bodyTextViewCached.font = [self textMessageFont];
    CGSize textSize = CGSizeCeil([self.bodyTextViewCached sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)]);
    CGFloat tapForMoreHeight = (self.displayableText.isTextTruncated ? [self tapForMoreHeight] : 0.f);
    CGSize textViewSize = CGSizeCeil(CGSizeMake(textSize.width + leftMargin + rightMargin,
        textSize.height + self.textTopMargin + self.textBottomMargin + tapForMoreHeight));

    return textViewSize;
}
//
//+ (CGSize)textSizeForContentWidth:(int)contentWidth
//                  displayableText:(DisplayableText *)displayableText
//                         textView:(OWSMessageTextView *)textView
//{
//    OWSAssert(text);
//    OWSAssert(textView);
//
//    BOOL isRTL = self.isRTL;
//    CGFloat leftMargin = isRTL ? self.textTrailingMargin : self.textLeadingMargin;
//    CGFloat rightMargin = isRTL ? self.textLeadingMargin : self.textTrailingMargin;
//
//    const int maxMessageWidth = [self maxMessageWidthForContentWidth:contentWidth];
//    const int maxTextWidth = (int)floor(maxMessageWidth - (leftMargin + rightMargin));
//
//    textView.text = displayableText.displayText;
//    // Honor dynamic type in the message bodies.
//    textView.font = [self textMessageFont];
//    CGSize textSize = CGSizeCeil([textView sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)]);
//    CGFloat tapForMoreHeight = (displayableText.isTextTruncated ? [self tapForMoreHeight] : 0.f);
//    CGSize textViewSize = CGSizeCeil(CGSizeMake(textSize.width + leftMargin + rightMargin,
//                                                textSize.height + self.textTopMargin + self.textBottomMargin +
//                                                tapForMoreHeight));
//
//    return textViewSize;
//}

- (CGSize)bodyMediaSizeForContentWidth:(int)contentWidth
{
    const int maxMessageWidth = [self maxMessageWidthForContentWidth:contentWidth];

    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage: {
            return CGSizeZero;
        }
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Video: {
            OWSAssert(self.mediaSize.width > 0);
            OWSAssert(self.mediaSize.height > 0);

            // TODO: Adjust this behavior.
            // TODO: This behavior is a bit different than the old behavior defined
            //       in JSQMediaItem+OWS.h.  Let's discuss.

            CGFloat contentAspectRatio = self.mediaSize.width / self.mediaSize.height;
            // Clamp the aspect ratio so that very thin/wide content is presented
            // in a reasonable way.
            const CGFloat minAspectRatio = 0.25f;
            const CGFloat maxAspectRatio = 1 / minAspectRatio;
            contentAspectRatio = MAX(minAspectRatio, MIN(maxAspectRatio, contentAspectRatio));

            const CGFloat maxMediaWidth = maxMessageWidth;
            const CGFloat maxMediaHeight = maxMessageWidth;
            CGFloat mediaWidth = (CGFloat)round(maxMediaHeight * contentAspectRatio);
            CGFloat mediaHeight = (CGFloat)round(maxMediaHeight);
            if (mediaWidth > maxMediaWidth) {
                mediaWidth = (CGFloat)round(maxMediaWidth);
                mediaHeight = (CGFloat)round(maxMediaWidth / contentAspectRatio);
            }
            return CGSizeMake(mediaWidth, mediaHeight);
        }
        case OWSMessageCellType_Audio:
            return CGSizeMake(maxMessageWidth, OWSAudioMessageView.bubbleHeight);
        case OWSMessageCellType_GenericAttachment:
            return CGSizeMake(maxMessageWidth, [OWSGenericAttachmentView bubbleHeight]);
        case OWSMessageCellType_DownloadingAttachment:
            return CGSizeMake(200, 90);
    }
}

- (int)maxMessageWidthForContentWidth:(int)contentWidth
{
    return (int)floor(contentWidth * 0.8f);
}

- (CGSize)cellSizeForViewWidth:(int)viewWidth contentWidth:(int)contentWidth
{
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    CGSize mediaContentSize = [self bodyMediaSizeForContentWidth:contentWidth];
    CGSize textContentSize = [self bodyTextSizeForContentWidth:contentWidth];

    CGFloat cellContentWidth = fmax(mediaContentSize.width, textContentSize.width);
    CGFloat cellContentHeight = mediaContentSize.height + textContentSize.height;
    CGSize cellSize = CGSizeMake(cellContentWidth, cellContentHeight);

    OWSAssert(cellSize.width > 0 && cellSize.height > 0);

    cellSize.height += self.dateHeaderHeight;
    cellSize.height += self.footerHeight;

    if (self.shouldHaveFailedSendBadge) {
        cellSize.width += self.failedSendBadgeSize;
    }

    cellSize.width = ceil(cellSize.width);
    cellSize.height = ceil(cellSize.height);

    return cellSize;
}

- (CGFloat)dateHeaderHeight
{
    if (self.viewItem.shouldShowDate) {
        // Add 5pt spacing above and below the date header.
        return MAX(self.dateHeaderDateFont.lineHeight, self.dateHeaderTimeFont.lineHeight) + 10.f;
    } else {
        return 0.f;
    }
}

#pragma mark -

- (BOOL)isIncoming
{
    return self.viewItem.interaction.interactionType == OWSInteractionType_IncomingMessage;
}

- (BOOL)isOutgoing
{
    return self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage;
}

- (CGFloat)textLeadingMargin
{
    return (self.isIncoming ? kBubbleTextHInset + kBubbleThornSideInset : kBubbleTextHInset);

    //    static const CGFloat kBubbleVRounding =  8.f;
    //    static const CGFloat kBubbleHRounding = 10.f;
    //    static const CGFloat kBubbleThornSideInset = 3.f;
    //    static const CGFloat kBubbleThornVInset = 3.f;
    //    static const CGFloat kBubbleTextHInset = 10.f;
    //    static const CGFloat kBubbleTextVInset = 10.f;
    //    static const CGFloat kBubbleTextTopInset = kBubbleTextVInset;
    //    static const CGFloat kBubbleTextBottomInset = kBubbleThornVInset + kBubbleTextVInset;

    //    return self.isIncoming ? 15 : 10;
}

- (CGFloat)textTrailingMargin
{
    return (self.isIncoming ? kBubbleTextHInset : kBubbleTextHInset + kBubbleThornSideInset);
    //    return self.isIncoming ? 10 : 15;
}

- (CGFloat)textTopMargin
{
    return kBubbleTextVInset;
}

- (CGFloat)textBottomMargin
{
    return kBubbleTextVInset + kBubbleThornVInset;
}

//- (CGFloat)textVMargin
//{
//    return 10;
//}

- (UIColor *)textColor
{
    return self.isIncoming ? [UIColor blackColor] : [UIColor whiteColor];
}

- (BOOL)isMediaBeingSent
{
    if (self.isIncoming) {
        return NO;
    }
    if (self.cellType == OWSMessageCellType_DownloadingAttachment) {
        return NO;
    }
    if (!self.attachmentStream) {
        return NO;
    }
    TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
    return outgoingMessage.messageState == TSOutgoingMessageStateAttemptingOut;
}

- (OWSMessagesBubbleImageFactory *)bubbleFactory
{
    return [OWSMessagesBubbleImageFactory shared];
}

- (void)prepareForReuse
{
    [super prepareForReuse];

    [NSLayoutConstraint deactivateConstraints:self.cellContentConstraints];
    self.cellContentConstraints = nil;
    [NSLayoutConstraint deactivateConstraints:self.bubbleContentConstraints];
    self.bubbleContentConstraints = [NSMutableArray new];
    [NSLayoutConstraint deactivateConstraints:self.dateHeaderConstraints];
    self.dateHeaderConstraints = nil;
    [NSLayoutConstraint deactivateConstraints:self.footerConstraints];
    self.footerConstraints = nil;

    self.dateHeaderLabel.text = nil;
    self.dateHeaderLabel.hidden = YES;
    [self.bodyTextViewCached removeFromSuperview];
    self.bodyTextViewCached.text = nil;
    self.bodyTextViewCached.hidden = YES;
    self.bodyTextViewCached.dataDetectorTypes = UIDataDetectorTypeNone;
    [self.failedSendBadgeView removeFromSuperview];
    self.failedSendBadgeView = nil;
    //    [self.tapForMoreLabel removeFromSuperview];
    //    self.tapForMoreLabel = nil;
    self.footerLabel.text = nil;
    self.footerLabel.hidden = YES;

    // TODO:
    self.bubbleView.hidden = YES;
    //<<<<<<< HEAD
    //    self.textBubbleImageView.image = nil;
    //    self.textBubbleImageView.hidden = YES;
    //    self.mediaMaskingView.maskedSubview = nil;
    //    self.mediaMaskingView.hideTail = NO;
    //    self.mediaMaskingView.layoutMargins = UIEdgeInsetsZero;
    //||||||| merged common ancestors
    //    self.bubbleImageView.image = nil;
    //    self.bubbleImageView.hidden = YES;
    //    self.payloadView.maskedSubview = nil;
    //=======
    //    self.bubbleFillView.hidden = YES;
    ////    self.bubbleImageView.image = nil;
    ////    self.bubbleImageView.hidden = YES;
    //    self.payloadView.maskedSubview = nil;
    //>>>>>>> SQUASHED

    for (UIView *subview in self.bubbleView.subviews) {
        [subview removeFromSuperview];
    }

    if (self.unloadCellContentBlock) {
        self.unloadCellContentBlock();
    }
    self.loadCellContentBlock = nil;
    self.unloadCellContentBlock = nil;

    //    [self.stillImageView removeFromSuperview];
    //    self.stillImageView = nil;
    //    [self.animatedImageView removeFromSuperview];
    //    self.animatedImageView = nil;
    //    [self.customView removeFromSuperview];
    //    self.customView = nil;
    //    [self.attachmentPointerView removeFromSuperview];
    //    self.attachmentPointerView = nil;
    //    [self.attachmentView removeFromSuperview];
    //    self.attachmentView = nil;
    //    [self.audioMessageView removeFromSuperview];
    //    self.audioMessageView = nil;
    //    [self.attachmentUploadView removeFromSuperview];
    //    self.attachmentUploadView = nil;
    [self.expirationTimerView clearAnimations];
    [self.expirationTimerView removeFromSuperview];
    self.expirationTimerView = nil;

    [self.lastImageView removeFromSuperview];
    self.lastImageView = nil;

    [self hideMenuControllerIfNecessary];
}

#pragma mark - Notifications

- (void)setIsCellVisible:(BOOL)isCellVisible {
    BOOL didChange = self.isCellVisible != isCellVisible;

    [super setIsCellVisible:isCellVisible];

    if (!didChange) {
        return;
    }

    [self ensureMediaLoadState];

    if (isCellVisible) {
        if (self.message.shouldStartExpireTimer) {
            [self.expirationTimerView ensureAnimations];
        } else {
            [self.expirationTimerView clearAnimations];
        }
    } else {
        [self.expirationTimerView clearAnimations];

        [self hideMenuControllerIfNecessary];
    }
}

#pragma mark - Gesture recognizers

- (void)handleTextTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAssert(self.delegate);

    if (sender.state != UIGestureRecognizerStateRecognized) {
        DDLogVerbose(@"%@ Ignoring tap on message: %@", self.logTag, self.viewItem.interaction.debugDescription);
        return;
    }

    if (self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
        if (outgoingMessage.messageState == TSOutgoingMessageStateUnsent) {
            [self.delegate didTapFailedOutgoingMessage:outgoingMessage];
            return;
        } else if (outgoingMessage.messageState == TSOutgoingMessageStateAttemptingOut) {
            // Ignore taps on outgoing messages being sent.
            return;
        }
    }

    if (self.hasText && self.displayableText.isTextTruncated) {
        [self.delegate didTapTruncatedTextMessage:self.viewItem];
        return;
    }
}

- (void)handleMediaTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAssert(self.delegate);

    if (sender.state != UIGestureRecognizerStateRecognized) {
        DDLogVerbose(@"%@ Ignoring tap on message: %@", self.logTag, self.viewItem.interaction.debugDescription);
        return;
    }

    if (self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
        if (outgoingMessage.messageState == TSOutgoingMessageStateUnsent) {
            [self.delegate didTapFailedOutgoingMessage:outgoingMessage];
            return;
        } else if (outgoingMessage.messageState == TSOutgoingMessageStateAttemptingOut) {
            // Ignore taps on outgoing messages being sent.
            return;
        }
    }

    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
            break;
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            if (self.displayableText.isTextTruncated) {
                [self.delegate didTapTruncatedTextMessage:self.viewItem];
                return;
            }
            break;
        case OWSMessageCellType_StillImage:
            OWSAssert(self.lastImageView);
            [self.delegate didTapImageViewItem:self.viewItem
                              attachmentStream:self.attachmentStream
                                     imageView:self.lastImageView];
            break;
        case OWSMessageCellType_AnimatedImage:
            OWSAssert(self.lastImageView);
            [self.delegate didTapImageViewItem:self.viewItem
                              attachmentStream:self.attachmentStream
                                     imageView:self.lastImageView];
            break;
        case OWSMessageCellType_Audio:
            [self.delegate didTapAudioViewItem:self.viewItem attachmentStream:self.attachmentStream];
            return;
        case OWSMessageCellType_Video:
            OWSAssert(self.lastImageView);
            [self.delegate didTapVideoViewItem:self.viewItem
                              attachmentStream:self.attachmentStream
                                     imageView:self.lastImageView];
            return;
        case OWSMessageCellType_GenericAttachment:
            [AttachmentSharing showShareUIForAttachment:self.attachmentStream];
            break;
        case OWSMessageCellType_DownloadingAttachment: {
            OWSAssert(self.attachmentPointer);
            if (self.attachmentPointer.state == TSAttachmentPointerStateFailed) {
                [self.delegate didTapFailedIncomingAttachment:self.viewItem attachmentPointer:self.attachmentPointer];
            }
            break;
        }
    }
}

- (void)handleTextLongPressGesture:(UILongPressGestureRecognizer *)sender
{
    OWSAssert(self.delegate);

    // We "eagerly" respond when the long press begins, not when it ends.
    if (sender.state == UIGestureRecognizerStateBegan) {
        CGPoint location = [sender locationInView:self];
        [self showTextMenuController:location];
    }
}

- (void)handleMediaLongPressGesture:(UILongPressGestureRecognizer *)sender
{
    OWSAssert(self.delegate);

    // We "eagerly" respond when the long press begins, not when it ends.
    if (sender.state == UIGestureRecognizerStateBegan) {
        CGPoint location = [sender locationInView:self];
        [self showMediaMenuController:location];
    }
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)panRecognizer
{
    OWSAssert(self.delegate);

    [self.delegate didPanWithGestureRecognizer:panRecognizer viewItem:self.viewItem];
}

#pragma mark - UIMenuController

- (void)showTextMenuController:(CGPoint)fromLocation
{
    // We don't want taps on messages to hide the keyboard,
    // so we only let messages become first responder
    // while they are trying to present the menu controller.
    self.isPresentingMenuController = YES;

    [self becomeFirstResponder];

    if ([UIMenuController sharedMenuController].isMenuVisible) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
    }

    // We use custom action selectors so that we can control
    // the ordering of the actions in the menu.
    NSArray *menuItems = self.viewItem.textMenuControllerItems;
    [UIMenuController sharedMenuController].menuItems = menuItems;
    CGRect targetRect = CGRectMake(fromLocation.x, fromLocation.y, 1, 1);
    [[UIMenuController sharedMenuController] setTargetRect:targetRect inView:self];
    [[UIMenuController sharedMenuController] setMenuVisible:YES animated:YES];
}

- (void)showMediaMenuController:(CGPoint)fromLocation
{
    // We don't want taps on messages to hide the keyboard,
    // so we only let messages become first responder
    // while they are trying to present the menu controller.
    self.isPresentingMenuController = YES;

    [self becomeFirstResponder];

    if ([UIMenuController sharedMenuController].isMenuVisible) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
    }

    // We use custom action selectors so that we can control
    // the ordering of the actions in the menu.
    NSArray *menuItems = self.viewItem.mediaMenuControllerItems;
    [UIMenuController sharedMenuController].menuItems = menuItems;
    CGRect targetRect = CGRectMake(fromLocation.x, fromLocation.y, 1, 1);
    [[UIMenuController sharedMenuController] setTargetRect:targetRect inView:self];
    [[UIMenuController sharedMenuController] setMenuVisible:YES animated:YES];
}

- (BOOL)canPerformAction:(SEL)action withSender:(nullable id)sender
{
    return [self.viewItem canPerformAction:action];
}

- (void)copyTextAction:(nullable id)sender
{
    [self.viewItem copyTextAction];
}

- (void)copyMediaAction:(nullable id)sender
{
    [self.viewItem copyMediaAction];
}

- (void)shareTextAction:(nullable id)sender
{
    [self.viewItem shareTextAction];
}

- (void)shareMediaAction:(nullable id)sender
{
    [self.viewItem shareMediaAction];
}

- (void)saveMediaAction:(nullable id)sender
{
    [self.viewItem saveMediaAction];
}

- (void)deleteAction:(nullable id)sender
{
    [self.viewItem deleteAction];
}

- (void)metadataAction:(nullable id)sender
{
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    [self.delegate showMetadataViewForViewItem:self.viewItem];
}

- (BOOL)canBecomeFirstResponder
{
    return self.isPresentingMenuController;
}

- (void)didHideMenuController:(NSNotification *)notification
{
    self.isPresentingMenuController = NO;
}

- (void)setIsPresentingMenuController:(BOOL)isPresentingMenuController
{
    if (_isPresentingMenuController == isPresentingMenuController) {
        return;
    }

    _isPresentingMenuController = isPresentingMenuController;

    if (isPresentingMenuController) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didHideMenuController:)
                                                     name:UIMenuControllerDidHideMenuNotification
                                                   object:nil];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:UIMenuControllerDidHideMenuNotification
                                                      object:nil];
    }
}

- (void)hideMenuControllerIfNecessary
{
    if (self.isPresentingMenuController) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
    }
    self.isPresentingMenuController = NO;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

NS_ASSUME_NONNULL_END
