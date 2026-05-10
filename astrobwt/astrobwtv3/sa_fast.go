package astrobwtv3

import "unsafe"
import "hash"
import "sync"

import "github.com/minio/sha256-simd"

const MAX_LENGTH uint32 = (256 * 384) - 1 // this is the maximum

// see here to improve the algorithms more https://github.com/y-256/libdivsufsort/blob/wiki/SACA_Benchmarks.md
// this optimized algorithm is used only  in the miner and not in the blockchain

type ScratchData struct {
	hasher   hash.Hash
	data     [MAX_LENGTH + 64]uint8
	sa       [MAX_LENGTH]int32
	sa_bytes *[(MAX_LENGTH) * 4]uint8
}

var Pool = sync.Pool{New: func() interface{} {
	var d ScratchData
	d.hasher = sha256.New()
	d.sa_bytes = ((*[(MAX_LENGTH) * 4]byte)(unsafe.Pointer(&d.sa[0])))

	return &d
}}

func text_32_0alloc(text []byte, sa []int32) {
	if int(int32(len(text))) != len(text) || len(text) != len(sa) {
		panic("suffixarray: misuse of text_16")
	}
	for i := range sa {
		sa[i] = 0
	}
	var memory [2 * 256]int32
	sais_8_32(text, 256, sa, memory[:])
}
