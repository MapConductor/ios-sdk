// The vector style compiler for the iOS SDK. Mirrors crates/mvt-style-ffi.
//
// Travels as a source header in ios-vectorstyle rather than inside the
// XCFramework: Xcode merges every linked framework's Headers into one include
// directory, and two frameworks shipping a module.modulemap collide there --
// which anything depending on both this and MvtRender would hit.
#ifndef MVT_STYLE_H
#define MVT_STYLE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Applies a rules document to a style document.
//
// Returns JSON: the adjusted style, the mutations, what they affect and the
// diagnostics -- or {"error": "..."} when either document could not be read.
// NULL only when an argument was not valid UTF-8 or the compiler panicked.
// Release the result with mvt_style_string_free.
char *mvt_style_compile(const char *style_json, const char *rules_json);

// The style's layers and the role each would be given, as a JSON array, or
// {"error": "..."}. Release with mvt_style_string_free.
char *mvt_style_describe(const char *style_json);

// The rules document version this library understands.
uint32_t mvt_style_schema_version(void);

// Releases a string this library returned. NULL is accepted.
void mvt_style_string_free(char *text);

#ifdef __cplusplus
}
#endif

#endif // MVT_STYLE_H
