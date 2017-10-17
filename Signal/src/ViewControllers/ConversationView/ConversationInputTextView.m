//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ConversationInputTextView.h"
#import "NSString+OWS.h"
#import "Signal-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface ConversationInputTextView () <UITextViewDelegate>

@property (nonatomic) UILabel *placeholderView;
@property (nonatomic) NSArray<NSLayoutConstraint *> *placeholderConstraints;
@property (nonatomic) BOOL isEditing;

@end

#pragma mark -

@implementation ConversationInputTextView

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self setTranslatesAutoresizingMaskIntoConstraints:NO];

        self.delegate = self;

        CGFloat cornerRadius = 6.0f;

        self.backgroundColor = [UIColor whiteColor];
        self.layer.borderColor = [UIColor lightGrayColor].CGColor;
        self.layer.borderWidth = 0.5f;
        self.layer.cornerRadius = cornerRadius;

        self.scrollIndicatorInsets = UIEdgeInsetsMake(cornerRadius, 0.0f, cornerRadius, 0.0f);

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
        self.returnKeyType = UIReturnKeySend;

        self.text = nil;

        self.placeholderView = [UILabel new];
        self.placeholderView.text = NSLocalizedString(@"new_message", @"");
        self.placeholderView.textColor = [UIColor lightGrayColor];
        self.placeholderView.textAlignment = NSTextAlignmentLeft;
        [self addSubview:self.placeholderView];

        // We need to do these steps _after_ placeholderView is configured.
        self.font = [UIFont ows_dynamicTypeBodyFont];
        self.textContainerInset = UIEdgeInsetsMake(4.0f, 2.0f, 4.0f, 2.0f);
        self.contentInset = UIEdgeInsetsMake(1.0f, 0.0f, 1.0f, 0.0f);

        [self ensurePlaceholderConstraints];
        [self updatePlaceholderVisibility];
    }

    return self;
}

- (void)setFont:(UIFont *_Nullable)font
{
    [super setFont:font];

    self.placeholderView.font = font;
}

- (void)setContentInset:(UIEdgeInsets)contentInset
{
    [super setContentInset:contentInset];

    [self ensurePlaceholderConstraints];
}

- (void)setTextContainerInset:(UIEdgeInsets)textContainerInset
{
    [super setTextContainerInset:textContainerInset];

    [self ensurePlaceholderConstraints];
}

- (void)ensurePlaceholderConstraints
{
    OWSAssert(self.placeholderView);

    if (self.placeholderConstraints) {
        [NSLayoutConstraint deactivateConstraints:self.placeholderConstraints];
    }

    // We align the location of our placeholder with the text content of
    // this view.  The only safe way to do that is by measuring the
    // beginning position.
    UITextRange *beginningTextRange =
        [self textRangeFromPosition:self.beginningOfDocument toPosition:self.beginningOfDocument];
    CGRect beginningTextRect = [self firstRectForRange:beginningTextRange];

    CGFloat hInset = beginningTextRect.origin.x;
    CGFloat topInset = beginningTextRect.origin.y;

    self.placeholderConstraints = @[
        [self.placeholderView autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:hInset],
        [self.placeholderView autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:hInset],
        [self.placeholderView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:topInset],
    ];
}

- (void)updatePlaceholderVisibility
{
    self.placeholderView.hidden = self.text.length > 0 || self.isEditing;
}

- (void)setText:(NSString *_Nullable)text
{
    [super setText:text];

    [self updatePlaceholderVisibility];
}

- (void)setIsEditing:(BOOL)isEditing
{
    _isEditing = isEditing;

    [self updatePlaceholderVisibility];
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
    return [self.text ows_stripped];
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

#pragma mark - UITextViewDelegate

- (void)textViewDidBeginEditing:(UITextView *)textView
{
    // TODO: Is this necessary?

    [textView becomeFirstResponder];

    self.isEditing = YES;
}

- (void)textViewDidChange:(UITextView *)textView
{
    OWSAssert(self.textViewToolbarDelegate);

    [self updatePlaceholderVisibility];

    [self.textViewToolbarDelegate textViewDidChange];
}

- (void)textViewDidEndEditing:(UITextView *)textView
{
    [textView resignFirstResponder];

    self.isEditing = NO;
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    OWSAssert(self.textViewToolbarDelegate);

    if (range.length > 0) {
        return YES;
    }
    if ([text isEqualToString:@"\n"]) {
        [self.textViewToolbarDelegate textViewReturnPressed];
        return NO;
    }
    return YES;
}

@end

NS_ASSUME_NONNULL_END
