#import "DialerViewController.h"

#import <MobileCoreServices/UTCoreTypes.h>

#import "ContactsManager.h"
#import "Environment.h"
#import "InCallViewController.h"
#import "InviteContactModal.h"
#import "LocalizableText.h"
#import "PhoneManager.h"
#import "PhoneNumberDirectoryFilter.h"
#import "PhoneNumberUtil.h"
#import "RecentCallManager.h"

#define INITIAL_BACKSPACE_TIMER_DURATION 0.5f
#define BACKSPACE_TIME_DECREASE_AMMOUNT 0.1f
#define FOUND_CONTACT_ANIMATION_DURATION 0.25f

#define E164_PREFIX @"+"

@interface DialerViewController ()

@property (strong, nonatomic) NSMutableString* currentNumberMutable;
@property (strong, nonatomic) Contact* contact;
@property (strong, nonatomic) NSTimer* backspaceTimer;
@property (strong, nonatomic) InviteContactModal* inviteModal;
@property (nonatomic) float backspaceDuration;

@end

@implementation DialerViewController

@synthesize matchedContactImageView = _matchedContactImageView;

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupPasteBehaviour];
    self.title = KEYPAD_NAV_BAR_TITLE;
    self.currentNumberMutable = [[NSMutableString alloc] init];
    [self updateNumberLabel];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [self.callButton setTitle:CALL_BUTTON_TITLE forState:UIControlStateNormal];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.phoneNumber) {
        self.currentNumberMutable = [self.phoneNumber.toE164 mutableCopy];
        [self updateNumberLabel];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.phoneNumber = nil;
}

- (void)setupPasteBehaviour {
    [self.numberLabel onPaste:^(id sender) {
        if ([[UIPasteboard generalPasteboard] containsPasteboardTypes:UIPasteboardTypeListString]) {
            [self.currentNumberMutable setString:[self sanitizePhoneNumberFromUnknownSource:[[UIPasteboard generalPasteboard] string]]];
            [self updateNumberLabel];
        }
    }];
}

- (NSString*)sanitizePhoneNumberFromUnknownSource:(NSString*)dirtyNumber {
    NSString* cleanNumber = [PhoneNumberUtil normalizePhoneNumber:dirtyNumber];
    
    if ([dirtyNumber hasPrefix:E164_PREFIX]) {
        cleanNumber = [NSString stringWithFormat:@"%@%@",E164_PREFIX,cleanNumber];
    }
    
    return cleanNumber;
}

#pragma mark - DialerButtonViewDelegate

- (void)dialerButtonViewDidSelect:(DialerButtonView*)view {
	[self.currentNumberMutable appendString:view.buttonInput];
	[self updateNumberLabel];
}

#pragma mark - Actions

- (void)backspaceButtonTouchDown {
	self.backspaceDuration = INITIAL_BACKSPACE_TIMER_DURATION;
	[self removeLastDigit];
}

- (void)backspaceButtonTouchUp {
	[self.backspaceTimer invalidate];
	self.backspaceTimer = nil;
}

- (void)removeLastDigit {
    NSUInteger n = self.currentNumberMutable.length;
    if (n > 0) {
        [self.currentNumberMutable deleteCharactersInRange:NSMakeRange(n - 1, 1)];
    }
    [self updateNumberLabel];

    self.backspaceDuration -= BACKSPACE_TIME_DECREASE_AMMOUNT;

    self.backspaceTimer = [NSTimer scheduledTimerWithTimeInterval:self.backspaceDuration
                                                       target:self
                                                     selector:@selector(removeLastDigit)
                                                     userInfo:nil
                                                      repeats:NO];
}

- (void)callButtonTapped {
    PhoneNumber* phoneNumber = self.phoneNumberForCurrentInput;

    BOOL shouldTryCall = [Environment.getCurrent.phoneDirectoryManager.getCurrentFilter containsPhoneNumber:phoneNumber] ||
                         [Environment.getCurrent.recentCallManager isPhoneNumberPresentInRecentCalls:phoneNumber];
    
    if (shouldTryCall) {
        [self initiateCallToPhoneNumber:phoneNumber];
    } else if (phoneNumber.isValid) {
        [self promptToInvitePhoneNumber:phoneNumber];
    }
}

- (void)initiateCallToPhoneNumber:(PhoneNumber*)phoneNumber {
    if (self.contact) {
        [Environment.phoneManager initiateOutgoingCallToContact:self.contact
                                                 atRemoteNumber:phoneNumber];
    } else {
        [Environment.phoneManager initiateOutgoingCallToRemoteNumber:phoneNumber];
    }
}

- (PhoneNumber*)phoneNumberForCurrentInput {
    NSString* numberText = [self.currentNumberMutable copy];
    
    if (numberText.length> 0 && [[numberText substringToIndex:1] isEqualToString:COUNTRY_CODE_PREFIX]) {
        return [PhoneNumber tryParsePhoneNumberFromE164:numberText];
    } else {
        return [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:numberText];
    }
}

- (void)updateNumberLabel {
    NSString* numberText = [self.currentNumberMutable copy];
    self.numberLabel.text = [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:numberText];
    PhoneNumber* number = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:numberText];	
    [self tryUpdateContactForNumber:number];
}

- (void)tryUpdateContactForNumber:(PhoneNumber*)number {
    if (number) {
        self.contact = [Environment.getCurrent.contactsManager latestContactForPhoneNumber:number];
    } else {
        self.contact = nil;
    }

    if (self.contact) {
        if (self.contact.image) {
            self.matchedContactImageView.alpha = 0.0f;
            self.matchedContactImageView.image = self.contact.image;
            [UIUtil applyRoundedBorderToImageView:&_matchedContactImageView];
            [UIView animateWithDuration:FOUND_CONTACT_ANIMATION_DURATION animations:^{
                self.matchedContactImageView.alpha = 1.0f;
            }];

        } else {
            [self removeContactImage];
        }
        
        [self.addContactButton setTitle:self.contact.fullName forState:UIControlStateNormal];
        
    } else {
        [self.addContactButton setTitle:@"" forState:UIControlStateNormal];
        [self removeContactImage];
    }
}

- (void)removeContactImage {
    [UIView animateWithDuration:FOUND_CONTACT_ANIMATION_DURATION animations:^{
        self.matchedContactImageView.alpha = 0.0f;
    } completion:^(BOOL finished) {
        [UIUtil removeRoundedBorderToImageView:&_matchedContactImageView];
        self.matchedContactImageView.image = nil;
    }];
}

- (void)promptToInvitePhoneNumber:(PhoneNumber*) phoneNumber {
    self.inviteModal = [[InviteContactModal alloc] initWithPhoneNumber:phoneNumber andParentViewController:self];
    [self.inviteModal presentModalView];
}


@end
