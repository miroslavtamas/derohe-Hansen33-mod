package main

import (
	"crypto/rand"
	"math/big"
	"testing"

	"github.com/deroproject/derohe/cryptography/crypto"
)

// TestCheckPowHashTargetEquivalence verifies that the allocation-free
// CheckPowHashTarget agrees with CheckPowHashBig on every random input,
// including edge cases at the threshold boundary.
func TestCheckPowHashTargetEquivalence(t *testing.T) {
	difficulties := []uint64{
		1,
		2,
		1000,
		1 << 32,
		1<<63 - 1,
	}
	for _, di := range difficulties {
		diff := new(big.Int).SetUint64(di)
		target := DifficultyToTarget(diff)

		var h crypto.Hash
		for i := 0; i < 1000; i++ {
			rand.Read(h[:])
			oldResult := CheckPowHashBig(h, diff)
			newResult := CheckPowHashTarget(h, &target)
			if oldResult != newResult {
				t.Fatalf("mismatch diff=%d hash=%x old=%v new=%v target=%x", di, h, oldResult, newResult, target)
			}
		}

		// Boundary: hash exactly at target.
		var atTarget crypto.Hash
		// target is big-endian; hash is little-endian. Reverse to construct.
		for i := 0; i < 32; i++ {
			atTarget[i] = target[31-i]
		}
		oldResult := CheckPowHashBig(atTarget, diff)
		newResult := CheckPowHashTarget(atTarget, &target)
		if oldResult != newResult {
			t.Fatalf("boundary mismatch diff=%d old=%v new=%v", di, oldResult, newResult)
		}
		if !newResult {
			t.Fatalf("boundary equality should pass diff=%d", di)
		}
	}
}

// BenchmarkCheckPowHashBig measures the per-call cost of the original
// big.Int-based check (allocates two big.Ints per call).
func BenchmarkCheckPowHashBig(b *testing.B) {
	diff := new(big.Int).SetUint64(1 << 30)
	var h crypto.Hash
	rand.Read(h[:])
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = CheckPowHashBig(h, diff)
	}
}

// BenchmarkCheckPowHashTarget measures the per-call cost of the
// allocation-free byte-comparison path.
func BenchmarkCheckPowHashTarget(b *testing.B) {
	diff := new(big.Int).SetUint64(1 << 30)
	target := DifficultyToTarget(diff)
	var h crypto.Hash
	rand.Read(h[:])
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = CheckPowHashTarget(h, &target)
	}
}
