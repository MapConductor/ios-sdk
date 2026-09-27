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
// Swift's C importer drops these: it keeps MVT_OK, which is a bare 0, but not
// macros whose body starts with a minus. MvtStatus in VectorTileRenderer.swift
// restates them for the Swift side; keep the two in step.
#define MVT_ERR_NULL_HANDLE (-1)
#define MVT_ERR_BAD_ARGUMENT (-2)
#define MVT_ERR_RENDER_FAILED (-3)
#define MVT_ERR_PANIC (-4)

/* Returns NULL on failure; *error_out then holds an owned message. */
/// `display_tile_size` is how many points one tile covers where the host shows
/// it -- not the pixel count a render is asked for (a label pass draws at twice
/// the pixels, and a 256pt tile is still 256pt however many pixels it carries).
/// It sets the size the style draws at and the zoom its expressions are read
/// at. Pass 0 for the usual 512.
MvtRenderer *mvt_renderer_new(const char *style_json,
                              uint32_t display_tile_size,
                              char **error_out);

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

/* JSON array of the credits the style's sources ask to be shown.
 *
 * The host must display these: a style is data under someone's licence. The
 * text may contain HTML, because a credit is normally a link to the licence. */
char *mvt_renderer_attributions(MvtRenderer *handle);

/* The style's `glyphs` URL template, or NULL when it names none. */
char *mvt_renderer_glyphs_url_template(MvtRenderer *handle);

/* JSON array of glyph-range URLs this tile's labels need and the store has not
 * got. Empty when the style names no template, or all of them are loaded.
 * Tiles are passed exactly as for mvt_renderer_render. */
char *mvt_renderer_needed_glyphs(MvtRenderer *handle,
                                 uint8_t z,
                                 uint32_t x,
                                 uint32_t y,
                                 const uint8_t *data,
                                 size_t data_len,
                                 const uint32_t *lengths,
                                 size_t lengths_len);

/* Adds one fetched glyph range PBF. Returns the glyph count, or < 0. */
int mvt_renderer_add_glyphs(MvtRenderer *handle, const uint8_t *pbf, size_t pbf_len);

/* 1 when any glyph is loaded, 0 when none, < 0 on failure. */
int mvt_renderer_has_glyphs(MvtRenderer *handle);

/* JSON array of the sprite sheet's [json, png] URLs at this pixel ratio, or []
 * when the style names no sprite. */
char *mvt_renderer_sprite_urls(MvtRenderer *handle, uint32_t pixel_ratio);

/* Adds the fetched sprite sheet. Returns the icon count, or < 0. */
int mvt_renderer_add_sprite(MvtRenderer *handle,
                            const char *json,
                            const uint8_t *png,
                            size_t png_len);

/* 1 when the style names a sprite the renderer has not been given yet. */
int mvt_renderer_needs_sprite(MvtRenderer *handle);

/* 1 when this tile must be drawn on the CPU because the style paints something
 * the GPU path cannot -- today, a patterned fill. */
int mvt_renderer_needs_cpu(MvtRenderer *handle,
                           uint8_t z,
                           const uint8_t *data,
                           size_t data_len,
                           const uint32_t *lengths,
                           size_t lengths_len);

/*
 * Rasterises the ground alone -- fills, lines and circles, no labels or icons.
 *
 * The half of a split layer that a GPU draws and that fonts arriving never
 * invalidate. Output and ownership match mvt_renderer_render.
 */
int mvt_renderer_render_geometry(MvtRenderer *handle,
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

/*
 * Draws labels and icons alone on a transparent ground, into a new
 * PREMULTIPLIED RGBA buffer of tile_size * tile_size * 4 bytes.
 *
 * The other half of a split layer: redrawn on its own when a font arrives,
 * leaving the ground untouched. *out_placed receives the label count; when it
 * is 0 nothing is allocated, *out_ptr stays NULL, and the caller should serve
 * one shared transparent tile. Encoding these pixels as straight alpha turns
 * every halo grey. Release with mvt_buffer_free.
 */
int mvt_renderer_render_labels(MvtRenderer *handle,
                               uint8_t z,
                               uint32_t x,
                               uint32_t y,
                               uint32_t tile_size,
                               const uint8_t *data,
                               size_t data_len,
                               const uint32_t *lengths,
                               size_t lengths_len,
                               uint8_t **out_ptr,
                               size_t *out_len,
                               size_t *out_placed);

/*
 * Draws labels and icons over pixels the caller already has, in place.
 *
 * `rgba` must hold exactly tile_size * tile_size * 4 bytes and is read as
 * STRAIGHT alpha, which is what a GPU readback is. Returns the label count,
 * or < 0.
 */
int mvt_renderer_draw_labels(MvtRenderer *handle,
                             uint8_t z,
                             uint32_t x,
                             uint32_t y,
                             uint32_t tile_size,
                             uint8_t *rgba,
                             size_t rgba_len,
                             const uint8_t *data,
                             size_t data_len,
                             const uint32_t *lengths,
                             size_t lengths_len);

/// Tessellates a tile into a packed float buffer for GPU drawing.
///
/// Layout, in floats:
///   [0]            extent in tile units
///   [1]            1.0 if the style has a background colour
///   [2..6]         background rgba
///   [6]            batch count B
///   [7..13]        timings: decode, tessellate, filter compile, fill, line, spare
///   [13..13+B*2]   per batch: first vertex, vertex count
///   [13+B*2..]     vertices: x, y, r, g, b, a
///
/// out_len counts floats, not bytes. Release with mvt_floats_free.
int32_t mvt_renderer_tessellate(struct MvtRenderer *handle,
                                uint8_t z,
                                uint32_t x,
                                uint32_t y,
                                uint32_t tile_size,
                                const uint8_t *data,
                                size_t data_len,
                                const uint32_t *lengths,
                                size_t lengths_len,
                                float **out_ptr,
                                size_t *out_len);


/// Releases a float buffer returned by mvt_renderer_tessellate.
void mvt_floats_free(float *ptr, size_t len);

void mvt_buffer_free(uint8_t *ptr, size_t len);
void mvt_string_free(char *text);

#ifdef __cplusplus
}
#endif

#endif /* MVT_RENDER_H */
