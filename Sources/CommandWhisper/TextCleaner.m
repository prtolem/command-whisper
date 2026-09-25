#import "TextCleaner.h"

@implementation CWTextCleaner

static NSString * const CWLineBreakMarker = @"\uE000";
static NSString * const CWParagraphBreakMarker = @"\uE001";

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

    text = [text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    text = [self replacePattern:@"\n{2,}" inText:text with:CWParagraphBreakMarker];
    text = [text stringByReplacingOccurrencesOfString:@"\n" withString:CWLineBreakMarker];
    text = [self expandSpokenPunctuation:text];

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
    text = [self replacePattern:@"\\s*([\\uE000\\uE001])\\s*" inText:text with:@"$1"];
    text = [self removeImmediateWordRepetitions:text];
    text = [self addRussianPunctuationHints:text];
    text = [self normalizePunctuation:text];
    text = [text stringByReplacingOccurrencesOfString:CWParagraphBreakMarker withString:@"\n\n"];
    text = [text stringByReplacingOccurrencesOfString:CWLineBreakMarker withString:@"\n"];
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    text = [self trimLoosePunctuation:text];
    if (text.length == 0) return @"";

    text = [self capitalizeSentences:text];
    return [self addTerminalPunctuationToLines:text];
}

+ (NSString *)expandSpokenPunctuation:(NSString *)text {
    NSArray<NSArray<NSString *> *> *rules = @[
        @[@"\\b(?:новый|следующий)\\s+абзац\\b", CWParagraphBreakMarker],
        @[@"\\b(?:новая|следующая)\\s+строка\\b", CWLineBreakMarker],
        @[@"\\bточка\\s+с\\s+запятой\\b", @";"],
        @[@"\\bвопросительный\\s+знак\\b", @"?"],
        @[@"\\bвосклицательный\\s+знак\\b", @"!"],
        @[@"\\b(?:открывающ(?:ая|ие)|открыть|открой)\\s+кавычк(?:а|и|у)\\b", @"«"],
        @[@"\\b(?:закрывающ(?:ая|ие)|закрыть|закрой)\\s+кавычк(?:а|и|у)\\b", @"»"],
        @[@"\\bмноготочие\\b", @"…"],
        @[@"\\bдвоеточие\\b", @":"],
        @[@"\\bзапятая\\b", @","],
        @[@"\\bтире\\b", @" — "],
        @[@"\\bточка\\b", @"."]
    ];
    for (NSArray<NSString *> *rule in rules) {
        text = [self replacePattern:rule[0] inText:text with:rule[1]];
    }
    return text;
}

+ (NSString *)addRussianPunctuationHints:(NSString *)text {
    text = [self replacePattern:@"\\bво\\s+первых\\b" inText:text with:@"во-первых"];
    text = [self replacePattern:@"\\bво\\s+вторых\\b" inText:text with:@"во-вторых"];
    text = [self replacePattern:@"\\bв\\s+третьих\\b" inText:text with:@"в-третьих"];

    NSString *breaks = @"\\uE000\\uE001";
    text = [self replacePattern:[NSString stringWithFormat:@"(?<![,.;:!?—%@])\\s+(но|а|зато|однако)\\s+", breaks]
                           inText:text
                             with:@", $1 "];
    text = [self replacePattern:@"(?<=[\\p{L}\\p{N}»])\\s+(потому\\s+что|так\\s+как|так\\s+что|что|чтобы|если|когда|пока|хотя|почему|зачем|где|куда|откуда|сколько|котор(?:ый|ая|ое|ые|ого|ой|ых|ому|ым|ую|ыми))\\s+"
                           inText:text
                             with:@", $1 "];

    NSArray<NSString *> *introductory = @[
        @"во-первых", @"во-вторых", @"в-третьих", @"например", @"конечно",
        @"наверное", @"вероятно", @"к сожалению", @"к счастью"
    ];
    for (NSString *word in introductory) {
        NSString *escaped = [NSRegularExpression escapedPatternForString:word];
        NSString *pattern = [NSString stringWithFormat:@"(^|[%@,.;:!?]\\s*)(%@)\\s+(?![,])", breaks, escaped];
        text = [self replacePattern:pattern inText:text with:@"$1$2, "];
        pattern = [NSString stringWithFormat:@"(?<=[\\p{L}\\p{N}»])\\s+(%@)\\s+(?=[\\p{L}\\p{N}«])", escaped];
        text = [self replacePattern:pattern inText:text with:@", $1, "];
    }
    text = [self replacePattern:@"^пожалуйста\\s+(?!,)" inText:text with:@"пожалуйста, "];
    text = [self replacePattern:@"\\s+пожалуйста(?=\\s*[,.;:!?\\uE000\\uE001]|$)" inText:text with:@", пожалуйста"];
    text = [self replacePattern:@"(?<=[\\p{L}\\p{N}»])\\s+пожалуйста\\s+(?=[\\p{L}\\p{N}«])" inText:text with:@", пожалуйста, "];
    return text;
}

+ (NSString *)normalizePunctuation:(NSString *)text {
    text = [self replacePattern:@"\\s+([,.;:!?…»])" inText:text with:@"$1"];
    text = [self replacePattern:@"«\\s+" inText:text with:@"«"];
    text = [self replacePattern:@"\\s*—\\s*" inText:text with:@" — "];
    text = [self replacePattern:@",{2,}" inText:text with:@","];
    text = [self replacePattern:@"!{2,}" inText:text with:@"!"];
    text = [self replacePattern:@"\\?{2,}" inText:text with:@"?"];
    text = [self replacePattern:@"\\.{3,}" inText:text with:@"…"];
    text = [self replacePattern:@"([,;:!?…])(?=[\\p{L}\\p{N}«])" inText:text with:@"$1 "];
    text = [self replacePattern:@"(?<!\\d)\\.(?=[\\p{L}\\p{N}«])" inText:text with:@". "];
    text = [self replacePattern:@"(?<=\\d)\\.(?=\\p{L})" inText:text with:@". "];
    text = [self replacePattern:@"[ \\t]{2,}" inText:text with:@" "];
    text = [self replacePattern:@"\\s*([\\uE000\\uE001])\\s*" inText:text with:@"$1"];
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
        if ([substring isEqualToString:@"\n"] || [[NSCharacterSet characterSetWithCharactersInString:@".!?…"] characterIsMember:[substring characterAtIndex:0]]) {
            capitalize = YES;
        } else if ([substring rangeOfCharacterFromSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]].location == NSNotFound
                   && substring.length > 0) {
            capitalize = NO;
        }
    }];
    return result;
}

+ (NSString *)addTerminalPunctuationToLines:(NSString *)text {
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *finished = [NSMutableArray arrayWithCapacity:lines.count];
    NSCharacterSet *terminal = [NSCharacterSet characterSetWithCharactersInString:@".!?…:;"];
    NSCharacterSet *closers = [NSCharacterSet characterSetWithCharactersInString:@")] }»\""];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length == 0) {
            [finished addObject:@""];
            continue;
        }
        NSInteger index = (NSInteger)trimmed.length - 1;
        while (index >= 0 && [closers characterIsMember:[trimmed characterAtIndex:(NSUInteger)index]]) index--;
        BOOL hasTerminal = index >= 0 && [terminal characterIsMember:[trimmed characterAtIndex:(NSUInteger)index]];
        if (!hasTerminal) {
            trimmed = [trimmed stringByAppendingString:[self looksLikeQuestion:trimmed] ? @"?" : @"."];
        }
        [finished addObject:trimmed];
    }
    return [finished componentsJoinedByString:@"\n"];
}

+ (BOOL)looksLikeQuestion:(NSString *)text {
    NSString *lower = [text.lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" «\""]];
    lower = [self replacePattern:@"^(?:скажи(?:те)?|подскажи(?:те)?)[,;:]?\\s+" inText:lower with:@""];
    NSArray<NSString *> *starts = @[@"кто ", @"что ", @"где ", @"когда ", @"куда ", @"откуда ", @"почему ", @"зачем ", @"как ", @"какой ", @"какая ", @"какое ", @"какие ", @"сколько ", @"можно ли ", @"есть ли ", @"правда ли ", @"можешь ли ", @"можете ли "];
    for (NSString *prefix in starts) if ([lower hasPrefix:prefix]) return YES;
    return NO;
}

@end
