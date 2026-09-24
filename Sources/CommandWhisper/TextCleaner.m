#import "TextCleaner.h"

@implementation CWTextCleaner

+ (NSString *)replacePattern:(NSString *)pattern inText:(NSString *)text with:(NSString *)replacement {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                            options:NSRegularExpressionCaseInsensitive
                                                                              error:&error];
    if (!regex || error) return text;
    return [regex stringByReplacingMatchesInString:text
                                           options:0
                                             range:NSMakeRange(0, text.length)
                                      withTemplate:replacement];
}

+ (NSString *)clean:(NSString *)source removeFillers:(BOOL)removeFillers {
    NSString *text = [source stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length == 0) return @"";

    if (removeFillers) {
        NSArray<NSString *> *patterns = @[
            @"\\b(?:э+|эм+|мм+|м-м+)\\b",
            @"\\b(?:ну|типа|короче|значит)\\b",
            @"\\b(?:как\\s+бы|это\\s+самое|в\\s+общем|в\\s+принципе)\\b"
        ];
        for (NSString *pattern in patterns) {
            text = [self replacePattern:pattern inText:text with:@" "];
        }
    }

    text = [self replacePattern:@"\\s+" inText:text with:@" "];
    text = [self removeImmediateWordRepetitions:text];
    text = [self replacePattern:@"\\s+([,.;:!?])" inText:text with:@"$1"];
    text = [self replacePattern:@"([,.;:!?])(?=[\\p{L}\\p{N}])" inText:text with:@"$1 "];
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    text = [self trimLoosePunctuation:text];
    if (text.length == 0) return @"";

    text = [self capitalizeSentences:text];
    unichar last = [text characterAtIndex:text.length - 1];
    NSCharacterSet *terminal = [NSCharacterSet characterSetWithCharactersInString:@".!?…:;)]}»\""];
    if (![terminal characterIsMember:last]) {
        text = [text stringByAppendingString:[self looksLikeQuestion:text] ? @"?" : @"."];
    }
    return text;
}

+ (NSString *)removeImmediateWordRepetitions:(NSString *)text {
    NSArray<NSString *> *parts = [text componentsSeparatedByString:@" "];
    NSMutableArray<NSString *> *kept = [NSMutableArray arrayWithCapacity:parts.count];
    NSString *previousWord = nil;
    NSCharacterSet *letters = NSCharacterSet.letterCharacterSet;
    for (NSString *part in parts) {
        NSString *word = [[part componentsSeparatedByCharactersInSet:letters.invertedSet] componentsJoinedByString:@""];
        if (word.length >= 1 && previousWord && [word caseInsensitiveCompare:previousWord] == NSOrderedSame) continue;
        [kept addObject:part];
        previousWord = word.length >= 1 ? word : nil;
    }
    return [kept componentsJoinedByString:@" "];
}

+ (NSString *)trimLoosePunctuation:(NSString *)text {
    NSCharacterSet *loose = [NSCharacterSet characterSetWithCharactersInString:@",.;:!? "];
    NSUInteger start = 0;
    while (start < text.length && [loose characterIsMember:[text characterAtIndex:start]]) start++;
    if (start == text.length) return @"";
    return [text substringFromIndex:start];
}

+ (NSString *)capitalizeSentences:(NSString *)text {
    NSMutableString *result = [NSMutableString stringWithCapacity:text.length];
    __block BOOL capitalize = YES;
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString *substring, NSRange _, NSRange __, BOOL *stop) {
        if (capitalize && [substring rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location != NSNotFound) {
            [result appendString:substring.uppercaseString];
            capitalize = NO;
        } else {
            [result appendString:substring];
        }
        if ([[@".!?…" componentsSeparatedByString:substring] count] > 1) {
            capitalize = YES;
        } else if ([substring rangeOfCharacterFromSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]].location == NSNotFound
                   && substring.length > 0) {
            capitalize = NO;
        }
    }];
    return result;
}

+ (BOOL)looksLikeQuestion:(NSString *)text {
    NSString *lower = text.lowercaseString;
    NSArray<NSString *> *starts = @[@"кто ", @"что ", @"где ", @"когда ", @"куда ", @"откуда ", @"почему ", @"зачем ", @"как ", @"какой ", @"какая ", @"какие ", @"сколько ", @"можно ли ", @"есть ли "];
    for (NSString *prefix in starts) if ([lower hasPrefix:prefix]) return YES;
    return NO;
}

@end
