//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ConversationInputTextView.h"
#import "Signal-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@implementation ConversationInputTextView

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self setTranslatesAutoresizingMaskIntoConstraints:NO];

        CGFloat cornerRadius = 6.0f;

        self.font = [UIFont ows_dynamicTypeBodyFont];
        self.backgroundColor = [UIColor whiteColor];
        self.layer.borderColor = [UIColor lightGrayColor].CGColor;
        self.layer.borderWidth = 0.5f;
        self.layer.cornerRadius = cornerRadius;

        self.scrollIndicatorInsets = UIEdgeInsetsMake(cornerRadius, 0.0f, cornerRadius, 0.0f);

        self.textContainerInset = UIEdgeInsetsMake(4.0f, 2.0f, 4.0f, 2.0f);
        self.contentInset = UIEdgeInsetsMake(1.0f, 0.0f, 1.0f, 0.0f);

        self.scrollEnabled = YES;
        self.scrollsToTop = NO;
        self.userInteractionEnabled = YES;

        self.font = [UIFont systemFontOfSize:16.0f];
        self.textColor = [UIColor blackColor];
        self.textAlignment = NSTextAlignmentNatural;

        self.contentMode = UIViewContentModeRedraw;
        self.dataDetectorTypes = UIDataDetectorTypeNone;
        self.keyboardAppearance = UIKeyboardAppearanceDefault;
        self.keyboardType = UIKeyboardTypeDefault;
        self.returnKeyType = UIReturnKeyDefault;

        self.text = nil;

        //        _placeHolder = nil;
        //        _placeHolderTextColor = [UIColor lightGrayColor];
    }

    return self;
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (BOOL)becomeFirstResponder
{
    BOOL becameFirstResponder = [super becomeFirstResponder];
    if (becameFirstResponder) {
        // Intercept to scroll to bottom when text view is tapped.
        [self.inputTextViewDelegate inputTextViewDidBecomeFirstResponder];
    }
    return becameFirstResponder;
}

- (BOOL)pasteboardHasPossibleAttachment
{
    // We don't want to load/convert images more than once so we
    // only do a cursory validation pass at this time.
    return ([SignalAttachment pasteboardHasPossibleAttachment] && ![SignalAttachment pasteboardHasText]);
}

- (BOOL)canPerformAction:(SEL)action withSender:(nullable id)sender
{
    if (action == @selector(paste:)) {
        if ([self pasteboardHasPossibleAttachment]) {
            return YES;
        }
    }
    return [super canPerformAction:action withSender:sender];
}

- (void)paste:(nullable id)sender
{
    if ([self pasteboardHasPossibleAttachment]) {
        SignalAttachment *attachment = [SignalAttachment attachmentFromPasteboard];
        // Note: attachment might be nil or have an error at this point; that's fine.
        [self.inputTextViewDelegate didPasteAttachment:attachment];
        return;
    }

    [super paste:sender];
}

- (void)setFrame:(CGRect)frame
{
    BOOL isNonEmpty = (self.width > 0.f && self.height > 0.f);
    BOOL didChangeSize = !CGSizeEqualToSize(frame.size, self.frame.size);

    [super setFrame:frame];

    if (didChangeSize && isNonEmpty) {
        [self.inputTextViewDelegate textViewDidChangeLayout];
    }
}

- (void)setBounds:(CGRect)bounds
{
    BOOL isNonEmpty = (self.width > 0.f && self.height > 0.f);
    BOOL didChangeSize = !CGSizeEqualToSize(bounds.size, self.bounds.size);

    [super setBounds:bounds];

    if (didChangeSize && isNonEmpty) {
        [self.inputTextViewDelegate textViewDidChangeLayout];
    }
}

- (NSString *)trimmedText
{
    return [self.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

// TODO:
//#import <QuartzCore/QuartzCore.h>
//
//#import "NSString+JSQMessages.h"
//
//
//@implementation JSQMessagesComposerTextView
//
//#pragma mark - Initialization
//
//- (void)jsq_configureTextView
//{
//
//    [self jsq_addTextViewNotificationObservers];
//}
//
//
//- (void)dealloc
//{
//    [self jsq_removeTextViewNotificationObservers];
//}
//
//#pragma mark - Composer text view
//
//- (BOOL)hasText
//{
//    return ([[self.text jsq_stringByTrimingWhitespace] length] > 0);
//}
//
//- (void)paste:(id)sender
//{
//    if (!self.jsqPasteDelegate || [self.jsqPasteDelegate composerTextView:self shouldPasteWithSender:sender]) {
//        [super paste:sender];
//    }
//}
//
//#pragma mark - Drawing
//
//- (void)drawRect:(CGRect)rect
//{
//    [super drawRect:rect];
//
//    if ([self.text length] == 0 && self.placeHolder) {
//        [self.placeHolderTextColor set];
//
//        [self.placeHolder drawInRect:CGRectInset(rect, 7.0f, 5.0f)
//                      withAttributes:[self jsq_placeholderTextAttributes]];
//    }
//}
//
//#pragma mark - Notifications
//
//- (void)jsq_addTextViewNotificationObservers
//{
//    [[NSNotificationCenter defaultCenter] addObserver:self
//                                             selector:@selector(jsq_didReceiveTextViewNotification:)
//                                                 name:UITextViewTextDidChangeNotification
//                                               object:self];
//
//    [[NSNotificationCenter defaultCenter] addObserver:self
//                                             selector:@selector(jsq_didReceiveTextViewNotification:)
//                                                 name:UITextViewTextDidBeginEditingNotification
//                                               object:self];
//
//    [[NSNotificationCenter defaultCenter] addObserver:self
//                                             selector:@selector(jsq_didReceiveTextViewNotification:)
//                                                 name:UITextViewTextDidEndEditingNotification
//                                               object:self];
//}
//
//- (void)jsq_removeTextViewNotificationObservers
//{
//    [[NSNotificationCenter defaultCenter] removeObserver:self
//                                                    name:UITextViewTextDidChangeNotification
//                                                  object:self];
//
//    [[NSNotificationCenter defaultCenter] removeObserver:self
//                                                    name:UITextViewTextDidBeginEditingNotification
//                                                  object:self];
//
//    [[NSNotificationCenter defaultCenter] removeObserver:self
//                                                    name:UITextViewTextDidEndEditingNotification
//                                                  object:self];
//}
//
//- (void)jsq_didReceiveTextViewNotification:(NSNotification *)notification
//{
//    [self setNeedsDisplay];
//}
//
//#pragma mark - Utilities
//
//- (NSDictionary *)jsq_placeholderTextAttributes
//{
//    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
//    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
//    paragraphStyle.alignment = self.textAlignment;
//
//    return @{ NSFontAttributeName : self.font,
//              NSForegroundColorAttributeName : self.placeHolderTextColor,
//              NSParagraphStyleAttributeName : paragraphStyle };
//}
//
//#pragma mark - UIMenuController
//
//- (BOOL)canBecomeFirstResponder
//{
//    return [super canBecomeFirstResponder];
//}
//
//- (BOOL)becomeFirstResponder
//{
//    return [super becomeFirstResponder];
//}
//
//- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
//    [UIMenuController sharedMenuController].menuItems = nil;
//    return [super canPerformAction:action withSender:sender];
//}
//@end

@end

NS_ASSUME_NONNULL_END
