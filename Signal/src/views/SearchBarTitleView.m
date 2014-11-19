#import "SearchBarTitleView.h"
#import "Environment.h"
#import "PreferencesUtil.h"
#import "LocalizableText.h"


#define SEARCH_BAR_ANIMATION_DURATION 0.25

@implementation SearchBarTitleView

- (void)awakeFromNib {
    [self localizeAndStyle];
    [self setupEvents];
}

- (void)localizeAndStyle {
    NSDictionary *labelAttributes = @{NSForegroundColorAttributeName:[UIColor grayColor]};

    _searchTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:TXT_SEARCH_PLACEHOLDER_TEXT
                                                                             attributes:labelAttributes];
    _searchTextField.tintColor = [UIColor grayColor];
}

- (void)setupEvents {
    _searchTextField.delegate = self;

    [_searchButton addTarget:self
                      action:@selector(searchButtonTapped)
            forControlEvents:UIControlEventTouchUpInside];

    [_cancelButton addTarget:self
                      action:@selector(cancelButtonTapped)
            forControlEvents:UIControlEventTouchUpInside];

    [_menuButton addTarget:self
                    action:@selector(menuButtonTapped)
          forControlEvents:UIControlEventTouchUpInside];
}

#pragma mark - Actions

- (void)searchButtonTapped {
    [UIView animateWithDuration:SEARCH_BAR_ANIMATION_DURATION animations:^{
        [_searchBarContainer setFrame:CGRectMake(0,
                                                 CGRectGetMinY(_searchBarContainer.frame),
                                                 CGRectGetWidth(_searchBarContainer.frame),
                                                 CGRectGetHeight(_searchBarContainer.frame))];
    } completion:^(BOOL finished) {
        [_searchTextField becomeFirstResponder];
    }];
}

- (void)cancelButtonTapped {
    [_delegate searchBarTitleViewDidEndSearching:self];
    [UIView animateWithDuration:SEARCH_BAR_ANIMATION_DURATION animations:^{
        [_searchBarContainer setFrame:CGRectMake(CGRectGetWidth(self.frame) - CGRectGetWidth(_searchButton.frame),
                                                 CGRectGetMinY(_searchBarContainer.frame),
                                                 CGRectGetWidth(_searchBarContainer.frame),
                                                 CGRectGetHeight(_searchBarContainer.frame))];
    } completion:^(BOOL finished) {
        _searchTextField.text = SEARCH_BAR_DEFAULT_EMPTY_STRING;
        [_searchTextField resignFirstResponder];
    }];	
}

- (void)updateAutoCorrectionType {
    BOOL autoCorrectEnabled = Environment.preferences.getAutocorrectEnabled;
    _searchTextField.autocorrectionType = autoCorrectEnabled ? UITextAutocorrectionTypeYes : UITextAutocorrectionTypeNo;
}

- (void)menuButtonTapped {
    [_delegate searchBarTitleViewDidTapMenu:self];
}

#pragma mark - UITextFieldDelegate

- (void)textFieldDidEndEditing:(UITextField *)textField {
    [textField resignFirstResponder];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
	
    BOOL searchTapped = [string rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location != NSNotFound;

    if(searchTapped) {
        [textField resignFirstResponder];
        return NO;
    }

    NSString *searchString = [textField.text stringByReplacingCharactersInRange:range withString:string];
    [_delegate searchBarTitleView:self didSearchForTerm:searchString];

    return YES;
}

@end
