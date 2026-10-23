// AES-128-CBC and SHA-1 for Wii U disc image extraction.
// Implemented on Windows CNG (bcrypt), which is part of the UWP API set:
// no desktop-only crypto APIs and no third-party code. AES and SHA-1
// providers are always installed on Windows; a CNG failure is treated as
// unrecoverable (see crypto.cpp).
#pragma once
#include <cstddef>
#include <cstdint>

namespace wudcrypto {

// An AES-128 key as 16 raw bytes.
struct Aes128Dec {
    uint8_t b[16];
    Aes128Dec() = default;
    explicit Aes128Dec(const uint8_t* raw) {
        for (int i = 0; i < 16; ++i) b[i] = raw[i];
    }
};

// In-place AES-128-CBC decryption; len must be a positive multiple of 16.
// The iv buffer is copied (CNG updates its working copy with the final
// ciphertext block, CBC semantics); callers pass a fresh IV per call.
void aes128_cbc_decrypt(const Aes128Dec& key, const uint8_t iv[16], void* data, size_t len);

// 20-byte SHA-1 of len bytes.
void sha1(const void* data, size_t len, uint8_t digest[20]);

}
