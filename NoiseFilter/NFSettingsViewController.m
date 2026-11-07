#import "NFSettingsViewController.h"
#import "NFService.h"
#import "NFHome.h"

typedef NS_ENUM(NSInteger, NFSection) {
    NFFilterSection, NFKeySection, NFCategoriesSection, NFStrictnessSection,
    NFInstructionsSection, NFActivitySection, NFSectionCount
};

@interface NFSettingsViewController () <UITextViewDelegate>
@end

@implementation NFSettingsViewController {
    NFService *_service;
    UITextView *_instructions;
    NSString *_keyNote, *_activityNote;
}
- (instancetype)initWithService:(NFService *)service {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _service = service;
    self.title = @"Noise filter";
    _instructions = [UITextView new];
    _instructions.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _instructions.backgroundColor = UIColor.clearColor;
    _instructions.text = service.instructions;
    _instructions.accessibilityIdentifier = @"noise-filter.instructions";
    _instructions.delegate = self;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(serviceChanged:) name:NFChanged object:service];
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        return trait.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:13/255.0 green:15/255.0 blue:22/255.0 alpha:1]
            : [UIColor colorWithRed:238/255.0 green:240/255.0 blue:246/255.0 alpha:1];
    }];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
}
- (void)serviceChanged:(NSNotification *)notification {
    if (!self.isViewLoaded) return;
    NSMutableIndexSet *sections = [NSMutableIndexSet indexSetWithIndex:NFKeySection];
    [sections addIndex:NFActivitySection];
    [UIView performWithoutAnimation:^{
        [self.tableView reloadSections:sections withRowAnimation:UITableViewRowAnimationNone];
        [self.tableView layoutIfNeeded];
    }];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return NFSectionCount; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ((NFSection)section) {
        case NFFilterSection: return 1;
        case NFKeySection: return _service.hasKey ? 2 : 1;
        case NFCategoriesSection: return _service.contract.categoryNames.count;
        case NFStrictnessSection: return _service.contract.strictnessNames.count;
        case NFInstructionsSection: return 2;
        case NFActivitySection: return 2;
        case NFSectionCount: return 0;
    }
    return 0;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"YouTube Home", @"TypeSafe API key", @"Hide", @"Strictness", @"Custom instructions", @"Activity"][section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch ((NFSection)section) {
        case NFFilterSection: return @"This diagnostic build does not hide videos yet. Capture Home diagnostics to identify the current app's video cards.";
        case NFKeySection:
            return _service.keyRejected ? @"TypeSafe rejected the key. Replace it to resume judging. Kept in this app's Keychain and sent only to api.typesafe.ai."
                                        : @"Kept in this app's Keychain and sent only to api.typesafe.ai. No key is supplied with the filter.";
        case NFStrictnessSection:
            return [NSString stringWithFormat:@"Model: %@. A score at or above this cutoff counts as noise for an enabled category or your instructions. Changing this reuses saved judgments.", _service.settings[@"model"]];
        case NFInstructionsSection:
            return [NSString stringWithFormat:@"%lu / %@ characters. Saved instructions apply to new judgments; previous instructions keep separate cached results.",
                    (unsigned long)_instructions.text.length, _service.contract.limits[@"guidance"]];
        case NFActivitySection: {
            NSDictionary *state = _service.diagnostics;
            NSString *error = state[@"lastError"] == NSNull.null ? @"" : [@"\n" stringByAppendingString:state[@"lastError"]];
            return [NSString stringWithFormat:@"%@ request attempts · %@ HTTP 200 responses · %lu saved judgments for these instructions\n%@ reported input tokens · %@ responses without usage%@%@",
                    state[@"requests"], state[@"responses"], (unsigned long)[state[@"verdicts"] count], state[@"inputTokens"],
                    state[@"responsesWithoutUsage"], error, _activityNote ? [@"\n" stringByAppendingString:_activityNote] : @""];
        }
        default: return nil;
    }
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    switch ((NFSection)index.section) {
        case NFFilterSection:
            content.text = @"Filter Home videos";
            cell.accessoryView = [self switchOn:_service.enabled action:@selector(toggleEnabled:) tag:0];
            cell.accessoryView.accessibilityIdentifier = @"noise-filter.enabled";
            break;
        case NFKeySection:
            content.text = index.row ? @"Remove key" : _service.hasKey ? @"Replace key" : @"Add key";
            content.textProperties.color = index.row ? UIColor.systemRedColor : self.view.tintColor;
            if (!index.row) {
                OSStatus status = _service.keychainStatus;
                content.secondaryText = _keyNote ?: (status != errSecSuccess && status != errSecItemNotFound
                    ? [NSString stringWithFormat:@"Keychain error (%d)", (int)status] : _service.hasKey ? @"Saved" : @"Not set");
            }
            break;
        case NFCategoriesSection: {
            NSString *name = _service.contract.categoryNames[index.row];
            content = [UIListContentConfiguration subtitleCellConfiguration];
            content.text = _service.contract.categories[name][@"label"];
            content.secondaryText = _service.contract.categories[name][@"summary"];
            cell.accessoryView = [self switchOn:[_service.settings[@"categories"][name] boolValue] action:@selector(toggleCategory:) tag:index.row];
            cell.accessoryView.accessibilityIdentifier = [@"noise-filter.category." stringByAppendingString:name];
            break;
        }
        case NFStrictnessSection: {
            NSString *level = _service.contract.strictnessNames[index.row];
            content.text = [NSString stringWithFormat:@"%@ · %.0f%%", level.capitalizedString, 100 * [_service.settings[@"thresholds"][level] doubleValue]];
            cell.accessoryType = [_service.settings[@"strictness"] isEqual:level] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            break;
        }
        case NFInstructionsSection:
            if (!index.row) {
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                _instructions.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:_instructions];
                UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
                [NSLayoutConstraint activateConstraints:@[
                    [_instructions.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
                    [_instructions.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
                    [_instructions.topAnchor constraintEqualToAnchor:margins.topAnchor],
                    [_instructions.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor],
                    [_instructions.heightAnchor constraintEqualToConstant:120]
                ]];
                return cell;
            } else {
                content.text = @"Save instructions";
                content.textProperties.color = self.view.tintColor;
            }
            break;
        case NFActivitySection:
            content.text = index.row ? @"Capture Home diagnostics" : @"Clear judgments";
            content.textProperties.color = index.row ? self.view.tintColor : UIColor.systemRedColor;
            break;
        case NFSectionCount: break;
    }
    cell.contentConfiguration = content;
    return cell;
}
- (UISwitch *)switchOn:(BOOL)on action:(SEL)action tag:(NSInteger)tag {
    UISwitch *control = [UISwitch new];
    control.on = on;
    control.tag = tag;
    [control addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return control;
}
- (void)toggleEnabled:(UISwitch *)control {
    NSMutableDictionary *settings = [_service.settings mutableCopy];
    NSMutableDictionary *sites = [settings[@"sites"] mutableCopy];
    sites[@"youtube"] = @(control.on);
    settings[@"sites"] = sites;
    [_service saveSettings:settings];
}
- (void)toggleCategory:(UISwitch *)control {
    NSMutableDictionary *settings = [_service.settings mutableCopy];
    NSMutableDictionary *categories = [settings[@"categories"] mutableCopy];
    categories[_service.contract.categoryNames[control.tag]] = @(control.on);
    settings[@"categories"] = categories;
    [_service saveSettings:settings];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tableView deselectRowAtIndexPath:index animated:YES];
    switch ((NFSection)index.section) {
        case NFKeySection:
            if (index.row) [self saveKey:@""]; else [self promptForKey];
            break;
        case NFStrictnessSection: {
            NSMutableDictionary *settings = [_service.settings mutableCopy];
            settings[@"strictness"] = _service.contract.strictnessNames[index.row];
            [_service saveSettings:settings];
            [tableView reloadSections:[NSIndexSet indexSetWithIndex:NFStrictnessSection] withRowAnimation:UITableViewRowAnimationNone];
            break;
        }
        case NFInstructionsSection:
            if (index.row) {
                [_service saveInstructions:_instructions.text];
                _instructions.text = _service.instructions;
                [_instructions resignFirstResponder];
                [self textViewDidChange:_instructions];
            }
            break;
        case NFActivitySection:
            if (index.row) [self saveDiagnostics];
            else {
                _activityNote = nil;
                [_service clearVerdicts];
            }
            break;
        default: break;
    }
}
- (void)promptForKey {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"TypeSafe API key" message:@"Enter your key from TypeSafe." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.secureTextEntry = YES;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.spellCheckingType = UITextSpellCheckingTypeNo;
        field.placeholder = @"API key";
        field.accessibilityIdentifier = @"noise-filter.api-key";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *key = weakAlert.textFields.firstObject.text;
        if ([key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) [weakSelf saveKey:key];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)saveKey:(NSString *)key {
    OSStatus status = [_service saveKey:key];
    _keyNote = status == errSecSuccess ? nil : [NSString stringWithFormat:@"Keychain error (%d); key unchanged", (int)status];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:NFKeySection] withRowAnimation:UITableViewRowAnimationNone];
}
- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    return textView.text.length - range.length + text.length <= [_service.contract.limits[@"guidance"] unsignedIntegerValue];
}
- (void)textViewDidChange:(UITextView *)textView {
    UITableViewHeaderFooterView *footer = [self.tableView footerViewForSection:NFInstructionsSection];
    footer.textLabel.text = [self tableView:self.tableView titleForFooterInSection:NFInstructionsSection];
    [footer setNeedsLayout];
}
- (void)saveDiagnostics {
    NSError *error;
    BOOL saved = NFCaptureHome(_service, &error);
    _activityNote = saved ? @"Return to Home and scroll. Up to eight visible-row observations are saved locally during the next minute. No key is included."
                          : [NSString stringWithFormat:@"Diagnostics not saved: %@", error.localizedDescription ?: @"Capture unavailable"];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:NFActivitySection] withRowAnimation:UITableViewRowAnimationNone];
}
@end
