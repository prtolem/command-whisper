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
        expect(@"привет запятая как дела вопросительный знак", YES, @"Привет, как дела?");
        expect(@"это важно восклицательный знак новый абзац проверь пожалуйста", YES, @"Это важно!\n\nПроверь, пожалуйста.");
        expect(@"я хотел прийти но не успел", YES, @"Я хотел прийти, но не успел.");
        expect(@"напиши мне когда будешь готов", YES, @"Напиши мне, когда будешь готов.");
        expect(@"я думаю что всё работает", YES, @"Я думаю, что всё работает.");
        expect(@"во первых это быстро запятая во вторых удобно", YES, @"Во-первых, это быстро, во-вторых, удобно.");
        expect(@"он сказал открыть кавычки всё готово закрыть кавычки", YES, @"Он сказал «всё готово».");
        expect(@"версия 2.5 уже готова", YES, @"Версия 2.5 уже готова.");
        expect(@"скажи почему это произошло", YES, @"Скажи, почему это произошло?");
        expect(@"это конечно работает", YES, @"Это, конечно, работает.");
        expect(@"проверь пожалуйста этот текст", YES, @"Проверь, пожалуйста, этот текст.");
        NSLog(@"TextCleaner: all tests passed");
    }
    return 0;
}
