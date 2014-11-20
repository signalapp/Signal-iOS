#import "SearchBarTitleView.h"
#import "Environment.h"
#import "PropertyListPreferences+Util.h"
#import "LocalizableText.h"

#import <UIViewController+MMDrawerController.h>

#define SEARCH_BAR_ANIMATION_DURATION 0.25

@implementation SearchBarTitleView

- (void)awakeFromNib {
    [self localizeAndStyle];
    [self setupEvents];
}

- (void)localizeAndStyle {
    NSDictionary* labelAttributes = @{NSForegroundColorAttributeName:UIColor.grayColor};

    self.searchTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:TXT_SEARCH_PLACEHOLDER_TEXT
                                                                                 attributes:labelAttributes];
    self.searchTextField.tintColor = UIColor.grayColor;
}

- (void)setupEvents {
    self.searchTextField.delegate = self;

    [self.searchButton addTarget:self
                          action:@selector(searchButtonTapped)
                forControlEvents:UIControlEventTouchUpInside];

    [self.cancelButton addTarget:self
                          action:@selector(cancelButtonTapped)
                forControlEvents:UIControlEventTouchUpInside];

    [self.menuButton addTarget:self
                        action:@selector(menuButtonTapped)
              forControlEvents:UIControlEventTouchUpInside];
}

#pragma mark - Actions

- (void)searchButtonTapped {
    [UIView animateWithDuration:SEARCH_BAR_ANIMATION_DURATION animations:^{
        [self.searchBarContainer setFrame:CGRectMake(0,
                                                 CGRectGetMinY(self.searchBarContainer.frame),
                                                 CGRectGetWidth(self.searchBarContainer.frame),
                                                 CGRectGetHeight(self.searchBarContainer.frame))];
    } completion:^(BOOL finished) {
        [self.searchTextField becomeFirstResponder];
    }];
}

- (void)cancelButtonTapped {
    id delegate = self.delegate;
    [delegate searchBarTitleViewDidEndSearching:self];
    [UIView animateWithDuration:SEARCH_BAR_ANIMATION_DURATION animations:^{
        [self.searchBarContainer setFrame:CGRectMake(CGRectGetWidth(self.frame) - CGRectGetWidth(self.searchButton.frame),
                                                     CGRectGetMinY(self.searchBarContainer.frame),
                                                     CGRectGetWidth(self.searchBarContainer.frame),
                                                     CGRectGetHeight(self.searchBarContainer.frame))];
    } completion:^(BOOL finished) {
        self.searchTextField.text = SEARCH_BAR_DEFAULT_EMPTY_STRING;
        [self.searchTextField resignFirstResponder];
    }];	
}

- (void)updateAutoCorrectionType {
    BOOL autoCorrectEnabled = Environment.preferences.getAutocorrectEnabled;
    self.searchTextField.autocorrectionType = autoCorrectEnabled ? UITextAutocorrectionTypeYes : UITextAutocorrectionTypeNo;
}

- (void)menuButtonTapped {
    id delegate = self.delegate;
    [delegate searchBarTitleViewDidTapMenu:self];
}

#pragma mark - UITextFieldDelegate

- (void)textFieldDidEndEditing:(UITextField*)textField {
    [textField resignFirstResponder];
}

- (BOOL)textField:(UITextField*)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString*)string {
	
    BOOL searchTapped = [string rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location != NSNotFound;

    if (searchTapped) {
        [textField resignFirstResponder];
        return NO;
    }

    NSString *searchString = [textField.text stringByReplacingCharactersInRange:range withString:string];
    id delegate = self.delegate;
    [delegate searchBarTitleView:self didSearchForTerm:searchString];

    return YES;
}

@end
