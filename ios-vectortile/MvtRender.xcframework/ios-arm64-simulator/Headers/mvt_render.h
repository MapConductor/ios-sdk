/*
 * C ABI for the MapConductor vector tile renderer.
 *
 * Rendering is split in two so no network I/O happens inside this library:
 * `mvt_renderer_plan` says which source tiles are needed, the caller fetches
 * them with its own networking stack, and `mvt_renderer_render` rasterises.
 *
 * Ownership: anything returned by pointer is Rust-allocated and must be
 * released with the matching free function. Calling free() on it is undefined.
 */
#ifndef MVT_RENDER_H
#define MVT_RENDER_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MvtRenderer MvtRenderer;

#define MVT_OK 0
#define MVT_ERR_NULL_HANDLE (-1)
#define MVT_ERR_BAD_ARGUMENT (-2)
#define MVT_ERR_RENDER_FAILED (-3)
#define MVT_ERR_PANIC (-4)

/* Returns NULL on failure; *error_out then holds an owned message. */
MvtRenderer *mvt_renderer_new(const char *style_json, char **error_out);

void mvt_renderer_free(MvtRenderer *handle);

/* Replaces the style. Fetched vector tiles stay valid: only paint changes. */
int mvt_renderer_set_style(MvtRenderer *handle,
                           const char *style_json,
                           char **error_out);

/* JSON array of { sourceId, url, z, x, y, scale, offsetX, offsetY }. */
char *mvt_renderer_plan(MvtRenderer *handle, uint8_t z, uint32_t x, uint32_t y);

/* JSON array of layer `type` values that will not be drawn. */
char *mvt_renderer_unsupported_layer_types(MvtRenderer *handle);

/* JSON array of reasons the style may not render as intended. */
char *mvt_renderer_diagnostics(MvtRenderer *handle);

/*
 * Rasterises one tile to PNG.
 *
 * `data` is every fetched source tile concatenated in plan order; `lengths`
 * gives each tile's byte length, 0 marking one that failed to fetch. On success
 * *out_ptr / *out_len receive a buffer to release with mvt_buffer_free.
 */
int mvt_renderer_render(MvtRenderer *handle,
                        uint8_t z,
                        uint32_t x,
                        uint32_t y,
                        uint32_t tile_size,
                        const uint8_t *data,
                        size_t data_len,
                        const uint32_t *lengths,
                        size_t lengths_len,
                        uint8_t **out_ptr,
                        size_t *out_len);

void mvt_buffer_free(uint8_t *ptr, size_t len);
void mvt_string_free(char *text);

#ifdef __cplusplus
}
#endif

#endif /* MVT_RENDER_H */
