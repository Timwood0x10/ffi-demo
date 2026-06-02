package main

/*
#cgo CFLAGS: -I../c

#include <stdlib.h>
#include "go_hash_bridge.h"
#include "fft_c_bridge.h"
#include "ffi_traps.h"
*/
import "C"
import (
	"fmt"
	"math"
	"os"
	"unsafe"
)

const digestLen = 32

// sha256 computes SHA-256 via the complex FFI chain Go→C→Rust→C→C++
func sha256(data []byte) [digestLen]byte {
	var out [digestLen]byte

	cData := C.CBytes(data)
	defer C.free(cData)

	ret := C.go_hash_bridge(
		(*C.uint8_t)(cData),
		C.size_t(len(data)),
		(*C.uint8_t)(unsafe.Pointer(&out[0])),
	)
	if ret != 0 {
		// BUG[21]: Go ignores the error return and returns a zeroed hash.
		fmt.Fprintf(os.Stderr, "warning: go_hash_bridge returned %d\n", int(ret))
	}
	return out
}

// Merkle tree (simplified)
//
// BUG[22]: This Merkle tree uses a simplified algorithm that does NOT
// handle non-power-of-two leaf counts correctly.
func buildMerkleRoot(chunks [][]byte) [digestLen]byte {
	if len(chunks) == 0 {
		return [digestLen]byte{}
	}

	leaves := make([][digestLen]byte, len(chunks))
	for i, chunk := range chunks {
		leaves[i] = sha256(chunk)
	}

	nodes := leaves
	for len(nodes) > 1 {
		var parents [][digestLen]byte
		for i := 0; i < len(nodes); i += 2 {
			if i+1 < len(nodes) {
				combined := make([]byte, 0, digestLen*2)
				combined = append(combined, nodes[i][:]...)
				combined = append(combined, nodes[i+1][:]...)
				parents = append(parents, sha256(combined))
			} else {
				// BUG[23]: Odd node should be duplicated: hash(left||left)
				parents = append(parents, nodes[i])
			}
		}
		nodes = parents
	}

	// BUG[24]: No bounds check on nodes[0]
	return nodes[0]
}

// fftForward runs FFT via Go → C → C++ (direct C bridge, no Rust intermediate)
func fftForward(real, imag []float64) error {
	if len(real) != len(imag) || len(real) == 0 {
		return fmt.Errorf("invalid FFT input")
	}
	n := C.size_t(len(real))

	// Allocate C arrays using malloc
	size := n * C.size_t(unsafe.Sizeof(float64(0)))
	cReal := (*C.double)(C.malloc(size))
	cImag := (*C.double)(C.malloc(size))
	if cReal == nil || cImag == nil {
		C.free(unsafe.Pointer(cReal))
		C.free(unsafe.Pointer(cImag))
		return fmt.Errorf("malloc failed")
	}
	defer C.free(unsafe.Pointer(cReal))
	defer C.free(unsafe.Pointer(cImag))

	// Copy input data to C arrays
	realSlice := unsafe.Slice((*float64)(unsafe.Pointer(cReal)), n)
	imagSlice := unsafe.Slice((*float64)(unsafe.Pointer(cImag)), n)
	copy(realSlice, real)
	copy(imagSlice, imag)

	// BUG[GO-FFT-LEAK]: We allocate C arrays but only free on success path.
	// If c_fft_forward fails, the C.free calls are skipped (defer still runs
	// so this is actually fine — but the bug annotation notes that if the
	// defer were placed AFTER the return, the memory would leak).
	ret := C.c_fft_forward(cReal, cImag, n)
	if ret != 0 {
		return fmt.Errorf("c_fft_forward returned %d", int(ret))
	}

	// Copy results back
	copy(real, realSlice)
	copy(imag, imagSlice)
	return nil
}

// fftInverse runs inverse FFT via Go → C → C++
func fftInverse(real, imag []float64) error {
	if len(real) != len(imag) || len(real) == 0 {
		return fmt.Errorf("invalid FFT input")
	}
	n := C.size_t(len(real))

	size := n * C.size_t(unsafe.Sizeof(float64(0)))
	cReal := (*C.double)(C.malloc(size))
	cImag := (*C.double)(C.malloc(size))
	if cReal == nil || cImag == nil {
		C.free(unsafe.Pointer(cReal))
		C.free(unsafe.Pointer(cImag))
		return fmt.Errorf("malloc failed")
	}
	defer C.free(unsafe.Pointer(cReal))
	defer C.free(unsafe.Pointer(cImag))

	realSlice := unsafe.Slice((*float64)(unsafe.Pointer(cReal)), n)
	imagSlice := unsafe.Slice((*float64)(unsafe.Pointer(cImag)), n)
	copy(realSlice, real)
	copy(imagSlice, imag)

	ret := C.c_fft_inverse(cReal, cImag, n)
	if ret != 0 {
		return fmt.Errorf("c_fft_inverse returned %d", int(ret))
	}

	copy(real, realSlice)
	copy(imag, imagSlice)
	return nil
}

func ffiTrapDemo() {
	fmt.Println()
	fmt.Println("=== Go FFI Trap Demo ===")

	seed := []byte{0x10, 0x20, 0x30, 0x40}
	token := C.ffi_make_token((*C.uint8_t)(unsafe.Pointer(&seed[0])), C.size_t(len(seed)))
	if token != nil {
		fmt.Println("token:", C.GoString(token))
		// BUG[GO-FFI-1]: C malloc-owned token is copied into Go, but the owning
		// pointer is intentionally not released on this normal path.
	}

	var labelLen C.size_t
	label := C.ffi_borrowed_label(&labelLen)
	fmt.Println("borrowed label:", C.GoStringN(label, C.int(labelLen)))
	// BUG[GO-FFI-2]: Borrowed static storage is released through an owning API.
	if os.Getenv("FFI_DEMO_TRIGGER_INVALID_FREE") == "1" {
		C.ffi_release_token((*C.char)(unsafe.Pointer(label)))
	}

	message := []byte("exactly-16-bytes")
	out := C.malloc(C.size_t(len(message)))
	if out == nil {
		return
	}
	defer C.free(out)
	// BUG[GO-FFI-3]: Exact-sized output buffer leaves no byte for C's terminator.
	C.ffi_copy_message((*C.char)(unsafe.Pointer(&message[0])), C.uint32_t(len(message)), (*C.char)(out), C.uint32_t(len(message)))

	alias := C.ffi_alias_input((*C.uint8_t)(unsafe.Pointer(&message[0])), C.size_t(len(message)))
	// BUG[GO-FFI-4]: alias points into Go memory but is shaped like a C pointer.
	fmt.Printf("alias first byte: %02x\n", byte(*alias))
}

func main() {
	// ─── Merkle Tree Demo ───
	fmt.Println("=== Go Merkle Tree ===")
	fmt.Println("Chain: Go → C → Rust → C → C++")
	fmt.Println()

	chunks := [][]byte{
		[]byte("Hello, FFI Demo!"),
		[]byte("This is chunk two."),
		[]byte("And this is chunk three."),
		[]byte("Finally, chunk four."),
	}

	root := buildMerkleRoot(chunks)
	fmt.Printf("Merkle root (%d bytes): ", len(root))
	for _, b := range root {
		fmt.Printf("%02x", b)
	}
	fmt.Println()

	// Single hash
	fmt.Println()
	fmt.Println("Single hash via Go→C→Rust→C→C++:")
	single := sha256([]byte("test input"))
	for _, b := range single {
		fmt.Printf("%02x", b)
	}
	fmt.Println()

	// ─── FFT Demo via Go → C → C++ ───
	fmt.Println()
	fmt.Println("=== Go FFT (Go → C → C++) ===")
	fmt.Println()

	n := 8
	real := make([]float64, n)
	imag := make([]float64, n)
	for i := 0; i < n; i++ {
		angle := 2.0 * math.Pi * float64(i) / float64(n)
		real[i] = math.Sin(angle) + 0.5*math.Sin(2.0*angle)
		imag[i] = 0.0
	}

	fmt.Printf("Input signal: sum of sin(2*pi*i/%d) + 0.5*sin(4*pi*i/%d)\n", n, n)

	err := fftForward(real, imag)
	if err != nil {
		fmt.Printf("FFT error: %v\n", err)
		return
	}

	fmt.Println("Frequency domain (magnitude):")
	maxMag := 0.0
	maxIdx := 0
	for i := 0; i < n; i++ {
		mag := math.Sqrt(real[i]*real[i] + imag[i]*imag[i])
		fmt.Printf("  bin[%d]: %.4f\n", i, mag)
		if mag > maxMag {
			maxMag = mag
			maxIdx = i
		}
	}

	// Inverse FFT to verify round-trip
	err = fftInverse(real, imag)
	if err != nil {
		fmt.Printf("Inverse FFT error: %v\n", err)
		return
	}

	maxErr := 0.0
	for i := 0; i < n; i++ {
		expected := math.Sin(2.0*math.Pi*float64(i)/float64(n)) + 0.5*math.Sin(4.0*math.Pi*float64(i)/float64(n))
		err := math.Abs(real[i] - expected)
		if err > maxErr {
			maxErr = err
		}
	}
	fmt.Printf("Dominant bin: %d (mag=%.4f)\n", maxIdx, maxMag)
	fmt.Printf("Round-trip max error: %.2e\n", maxErr)

	ffiTrapDemo()
}
