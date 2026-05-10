//go:build !cgo
// +build !cgo

package astrobwtv3

// text_32_libsais falls back to the pure-Go SA-IS when cgo is disabled.
func text_32_libsais(text []byte, sa []int32) {
	text_32_0alloc(text, sa)
}
