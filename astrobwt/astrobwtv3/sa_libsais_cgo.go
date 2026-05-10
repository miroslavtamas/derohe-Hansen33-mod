//go:build cgo
// +build cgo

package astrobwtv3

/*
#cgo CFLAGS: -O3 -DNDEBUG -I${SRCDIR}/libsais
#cgo amd64 CFLAGS: -march=haswell
#include "libsais/libsais.h"
*/
import "C"

import (
	"sync"
	"unsafe"
)

// libsais maintains an internal scratch (free space) used while building
// the suffix array. The no-ctx libsais entry point allocates and frees that
// scratch on every call. libsais_ctx lets us pre-allocate once and reuse.
// We keep one context per goroutine via a sync.Pool so the SA pool and the
// libsais pool stay decoupled from each other and from sa_fast.go's
// ScratchData lifecycle.
var libsaisCtxPool = sync.Pool{
	New: func() interface{} {
		ctx := C.libsais_create_ctx()
		if ctx == nil {
			panic("libsais_create_ctx returned NULL")
		}
		return ctx
	},
}

// text_32_libsais constructs the suffix array of `text` into `sa` using
// the vendored libsais sources compiled in via cgo. Output is identical
// to the in-tree text_32_0alloc / sais_8_32 path because the suffix array
// of a byte string is uniquely defined.
//
// The caller can pass a sa slice with cap(sa) > len(sa); the unused tail
// is handed to libsais as free workspace via the `fs` argument, which
// lets libsais skip its slow internal-allocation paths.
func text_32_libsais(text []byte, sa []int32) {
	if len(text) != len(sa) {
		panic("suffixarray: text/sa length mismatch")
	}
	if len(text) == 0 {
		return
	}
	fs := cap(sa) - len(sa)
	ctx := libsaisCtxPool.Get().(unsafe.Pointer)
	ret := C.libsais_ctx(
		ctx,
		(*C.uint8_t)(unsafe.Pointer(&text[0])),
		(*C.int32_t)(unsafe.Pointer(&sa[0])),
		C.int32_t(len(text)),
		C.int32_t(fs),
		nil,
	)
	libsaisCtxPool.Put(ctx)
	if ret != 0 {
		panic("libsais_ctx failed")
	}
}
