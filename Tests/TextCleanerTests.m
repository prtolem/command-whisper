#import <Foundation/Foundation.h>
#import "TextCleaner.h"

static void expect(NSString *input, BOOL removeFillers, NSString *expected) {
    NSString *actual = [CWTextCleaner clean:input removeFillers:removeFillers];
    if (![actual isEqualToString:expected]) {
        NSLog(@"FAIL\n input: %@\nactual: %@\nexpect: %@", input, actual, expected);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        expect(@"ну типа я я хочу сделать это", YES, @"Я хочу сделать это.");
        expect(@"это охуенно работает", YES, @"Это охуенно работает.");
        expect(@"почему это не работает", YES, @"Почему это не работает?");
        expect(@"ну вот так", NO, @"Ну вот так.");
        NSLog(@"TextCleaner: all tests passed");
    }
    return 0;
}
