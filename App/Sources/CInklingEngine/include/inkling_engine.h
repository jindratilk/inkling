#ifndef INKLING_ENGINE_H
#define INKLING_ENGINE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct InklingEngine InklingEngine;

/// Create an engine from a JSON configuration. Never returns NULL.
InklingEngine *inkling_engine_new(const char *config_json);
void inkling_engine_free(InklingEngine *engine);

/// Lint UTF-8 text. Returns JSON; free with inkling_string_free.
char *inkling_engine_check(InklingEngine *engine, const char *text);
bool inkling_engine_is_word_known(InklingEngine *engine, const char *word);

/// JSON object of { rule: description }. Free with inkling_string_free.
char *inkling_engine_rule_descriptions(InklingEngine *engine);
/// JSON array of coach lessons. Free with inkling_string_free.
char *inkling_coach_lessons(void);

void inkling_string_free(char *s);

#ifdef __cplusplus
}
#endif

#endif
