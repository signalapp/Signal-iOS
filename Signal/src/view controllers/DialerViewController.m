#import "DialerViewController.h"

#import <MobileCoreServices/UTCoreTypes.h>

#import "ContactsManager.h"
#import "Environment.h"
#import "InCallViewController.h"
#import "LocalizableText.h"
#import "PhoneManager.h"
#import "PhoneNumberDirectoryFilter.h"
#import "PhoneNumberUtil.h"
#import "RecentCallManager.h"

#define INITIAL_BACKSPACE_TIMER_DURATION 0.5f
#define BACKSPACE_TIME_DECREASE_AMMOUNT 0.1f
#define FOUND_CONTACT_ANIMATION_DURATION 0.25f

#define E164_PREFIX @"+"

@interface DialerViewController () {
    NSMutableString *_currentNumberMutable;
    Contact *_contact;
    NSTimer *_backspaceTimer;
    float _backspaceDuration;
    
}

@end

@implementation DialerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupPasteBehaviour];
    self.title = KEYPAD_NAV_BAR_TITLE;
    _currentNumberMutable = [NSMutableString string];
    //[self updateNumberLabel];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [_callButton setTitle:CALL_BUTTON_TITLE forState:UIControlStateNormal];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UIBlurEffect * effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
    UIVisualEffectView * viewWithBlurredBackground =
    [[UIVisualEffectView alloc] initWithEffect:effect];
    viewWithBlurredBackground.frame = self.view.frame;
    
    [self.view insertSubview:viewWithBlurredBackground atIndex:0];
    
    if (_phoneNumber) {
        _currentNumberMutable = _phoneNumber.toE164.mutableCopy;
        [self updateNumberLabel];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _phoneNumber = nil;
}

- (void)setupPasteBehaviour {
    [self.numberLabel onPaste:^(id sender) {
        
        [UIPasteboard generalPasteboard];
        if([[UIPasteboard generalPasteboard] containsPasteboardTypes:UIPasteboardTypeListString]){
            [_currentNumberMutable setString:[self sanitizePhoneNumberFromUnknownSource:[[UIPasteboard generalPasteboard] string]]];
            [self updateNumberLabel];
        }
    }];
}

-(NSString*) sanitizePhoneNumberFromUnknownSource:(NSString*) dirtyNumber {
    NSString* cleanNumber = [PhoneNumberUtil normalizePhoneNumber:dirtyNumber];
    
    if ([dirtyNumber hasPrefix:E164_PREFIX]) {
        cleanNumber = [NSString stringWithFormat:@"%@%@",E164_PREFIX,cleanNumber];
    }
    
    return cleanNumber;
}

#pragma mark - DialerButtonViewDelegate

- (void)dialerButtonViewDidSelect:(DialerButtonView *)view {
	[_currentNumberMutable appendString:view.buttonInput];
	[self updateNumberLabel];
}

#pragma mark - Actions

- (void)backspaceButtonTouchDown {
	_backspaceDuration = INITIAL_BACKSPACE_TIMER_DURATION;
	[self removeLastDigit];
}

- (void)backspaceButtonTouchUp {
	[_backspaceTimer invalidate];
	_backspaceTimer = nil;
}

- (void)removeLastDigit {
    NSUInteger n = _currentNumberMutable.length;
    if (n > 0) {
        [_currentNumberMutable deleteCharactersInRange:NSMakeRange(n - 1, 1)];
    }
    [self updateNumberLabel];

    _backspaceDuration -= BACKSPACE_TIME_DECREASE_AMMOUNT;

    _backspaceTimer = [NSTimer scheduledTimerWithTimeInterval:_backspaceDuration
                                                       target:self
                                                     selector:@selector(removeLastDigit)
                                                     userInfo:nil
                                                      repeats:NO];
}

- (void)callButtonTapped {
    
    PhoneNumber *phoneNumber = self.phoneNumberForCurrentInput;

    BOOL shouldTryCall = [Environment.getCurrent.phoneDirectoryManager.getCurrentFilter containsPhoneNumber:phoneNumber] || [Environment.getCurrent.recentCallManager isPhoneNumberPresentInRecentCalls:phoneNumber];
    
    if( shouldTryCall){
        [self initiateCallToPhoneNumber:phoneNumber];
    }else if(phoneNumber.isValid){
        [self promptToInvitePhoneNumber:phoneNumber];
    }
}


-(IBAction)cancelButtonTapped:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(void) initiateCallToPhoneNumber:(PhoneNumber*) phoneNumber {
    if (_contact) {
        [Environment.phoneManager initiateOutgoingCallToContact:_contact
                                                   atRemoteNumber:phoneNumber];
    } else {
        [Environment.phoneManager initiateOutgoingCallToRemoteNumber:phoneNumber];
    }
}

- (PhoneNumber *)phoneNumberForCurrentInput {
    NSString *numberText = [_currentNumberMutable copy];
    
    if (numberText.length> 0 && [[numberText substringToIndex:1] isEqualToString:COUNTRY_CODE_PREFIX]) {
        return [PhoneNumber tryParsePhoneNumberFromE164:numberText];
    } else {
        return [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:numberText];
    }
}

- (void)updateNumberLabel {
    //DEBUG!!!
    NSString* numberText = [_currentNumberMutable copy];
    
    _numberLabel.text = [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:numberText];
    PhoneNumber* number = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:numberText];	
    [self tryUpdateContactForNumber:number];
}

- (void)tryUpdateContactForNumber:(PhoneNumber *)number {
    if (number) {
        _contact = [Environment.getCurrent.contactsManager latestContactForPhoneNumber:number];
    } else {
        _contact = nil;
    }

    if (_contact) {
        if (_contact.image) {
            _matchedContactImageView.alpha = 0.0f;
            _matchedContactImageView.image = _contact.image;
            [UIUtil applyRoundedBorderToImageView:&_matchedContactImageView];
            [UIView animateWithDuration:FOUND_CONTACT_ANIMATION_DURATION animations:^{
                _matchedContactImageView.alpha = 1.0f;
            }];

        } else {
            [self removeContactImage];
        }
        
        [_addContactButton setTitle:_contact.fullName forState:UIControlStateNormal];
        
    } else {
        [_addContactButton setTitle:@"" forState:UIControlStateNormal];
        [self removeContactImage];
    }
}

- (void)removeContactImage {
    [UIView animateWithDuration:FOUND_CONTACT_ANIMATION_DURATION animations:^{
        _matchedContactImageView.alpha = 0.0f;
    } completion:^(BOOL finished) {
        [UIUtil removeRoundedBorderToImageView:&_matchedContactImageView];
        _matchedContactImageView.image = nil;
    }];
}

-(void) promptToInvitePhoneNumber:(PhoneNumber*) phoneNumber {
    // TODO
}


@end
