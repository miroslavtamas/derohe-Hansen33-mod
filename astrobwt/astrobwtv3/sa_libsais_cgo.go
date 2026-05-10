//go:build cgo
// +build cgo

package astrobwtv3

/*
#cgo CFLAGS: -O3 -DNDEBUG -I${SRCDIR}/libsais
#include "libsais/libsais.h"
*/
import "C"

import "unsafe"

// text_32_libsais constructs the suffix array of `text` into `sa` using
// the vendored libsais sources compiled in via cgo. Output is identical
// to the in-tree text_32_0alloc / sais_8_32 path because the suffix array
// of a byte string is uniquely defined.
func text_32_libsais(text []byte, sa []int32) {
	if len(text) != len(sa) {
		panic("suffixarray: text/sa length mismatch")
	}
	if len(text) == 0 {
		return
	}
	ret := C.libsais(
		(*C.uint8_t)(unsafe.Pointer(&text[0])),
		(*C.int32_t)(unsafe.Pointer(&sa[0])),
		C.int32_t(len(text)),
		0,
		nil,
	)
	if ret != 0 {
		panic("libsais failed")
	}
}
