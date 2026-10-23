// AES-128-CBC and SHA-1 on Windows CNG for the embedded disc-image extractor.
// One-shot CNG calls with internally allocated key/hash objects keep this small;
// UWP allows bcrypt (it is part of the app API set).
#include "crypto.h"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <bcrypt.h>
#pragma comment(lib, "bcrypt")

#include <cstdlib>

namespace wudcrypto {
namespace {

// AES and SHA-1 providers are always present on Windows; reaching a failure here
// means a system-level problem the extractor can neither report nor recover from.
void check(NTSTATUS status) {
    if (status < 0) std::abort();
}

}

void aes128_cbc_decrypt(const Aes128Dec& key, const uint8_t iv[16], void* data, size_t len) {
    if (len == 0) return;
    if (len % 16 != 0 || len > 0xFFFFFFFFull) std::abort();

    BCRYPT_ALG_HANDLE alg = nullptr;
    check(BCryptOpenAlgorithmProvider(&alg, BCRYPT_AES_ALGORITHM, nullptr, 0));
    // The default chaining mode is ECB: switch to CBC before key generation.
    check(BCryptSetProperty(alg, BCRYPT_CHAINING_MODE,
                            (PUCHAR)BCRYPT_CHAIN_MODE_CBC, sizeof(BCRYPT_CHAIN_MODE_CBC), 0));
    BCRYPT_KEY_HANDLE hkey = nullptr;
    check(BCryptGenerateSymmetricKey(alg, &hkey, nullptr, 0, (PUCHAR)key.b, 16, 0));

    // CNG updates the IV in place: give it a mutable copy.
    uint8_t iv_work[16];
    for (int i = 0; i < 16; ++i) iv_work[i] = iv[i];

    ULONG done = 0;
    NTSTATUS status = BCryptDecrypt(hkey, (PUCHAR)data, (ULONG)len, nullptr,
                                   iv_work, 16, (PUCHAR)data, (ULONG)len, &done, 0);
    BCryptDestroyKey(hkey);
    BCryptCloseAlgorithmProvider(alg, 0);
    check(status);
    if (done != len) std::abort();
}

void sha1(const void* data, size_t len, uint8_t digest[20]) {
    if (len > 0xFFFFFFFFull) std::abort();
    BCRYPT_ALG_HANDLE alg = nullptr;
    check(BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA1_ALGORITHM, nullptr, 0));
    BCRYPT_HASH_HANDLE hash = nullptr;
    check(BCryptCreateHash(alg, &hash, nullptr, 0, nullptr, 0, 0));
    NTSTATUS status = BCryptHashData(hash, (PUCHAR)data, (ULONG)len, 0);
    if (status >= 0) status = BCryptFinishHash(hash, digest, 20, 0);
    BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(alg, 0);
    check(status);
}

}
