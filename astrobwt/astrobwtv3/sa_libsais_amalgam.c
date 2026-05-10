/* Amalgamation wrapper that pulls vendored libsais sources into the cgo
 * compilation unit. Cgo only auto-compiles .c files at the package root,
 * so we re-include the real implementation from the libsais/ subdirectory. */

#include "libsais/libsais.c"
