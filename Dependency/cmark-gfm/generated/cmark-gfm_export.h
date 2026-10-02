/* Hand-written replacement for the header CMake generates. MacDown links
 * cmark-gfm statically, so the export macros only control visibility. */
#ifndef CMARK_GFM_EXPORT_H
#define CMARK_GFM_EXPORT_H

#define CMARK_GFM_EXPORT
#define CMARK_GFM_NO_EXPORT __attribute__((visibility("hidden")))

#ifndef CMARK_GFM_DEPRECATED
#define CMARK_GFM_DEPRECATED __attribute__((__deprecated__))
#endif

#endif
