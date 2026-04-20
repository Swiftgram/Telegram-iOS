# Pure-Python port of `decrypt.rb` for fastlane match

## Goal

Drop the Ruby toolchain dependency from the iOS build. Replace the `ruby build-system/decrypt.rb` call in `BuildConfiguration.py:110` with a self-contained Python 3 implementation. No new third-party dependencies (no `cryptography` package, no Ruby).

## Current state

- `build-system/decrypt.rb` (115 lines) implements fastlane match's V1 (AES-256-CBC via `pkcs5_keyivgen` with MD5→SHA256 fallback) and V2 (AES-256-GCM with PBKDF2-derived key/iv/AAD + auth tag) decryption.
- `BuildConfiguration.py:103-118`'s `decrypt_codesigning_directory_recursively` shells out via `os.system('ruby build-system/decrypt.rb …')` per file.
- `build-system/Make/DecryptMatch.py` already exists as an aspirational Python port but is broken — its V2 implementation writes a literal placeholder string (`b"TEST_DECRYPTED_CONTENT"`) and the call site in `BuildConfiguration.py:115` is commented out.
- The production fastlane repo at `git@gitlab.com:peter-iakovlev/fastlanematch.git` stores files in V2 format (verified: base64 prefix decodes to `match_encrypted_v2__`). V2 must work.

## Constraints

- Stock macOS `python3` (3.9.6). Only Python stdlib may be used (`hashlib`, `hmac`, `base64`, `os`).
- Apple-shipped `openssl enc` CLI rules out the shell-out path for V2 because it does not accept AAD for GCM.
- The Ruby script's semantics are authoritative; the port must be byte-identical on the existing repo contents.

## Approach

Rewrite `build-system/Make/DecryptMatch.py` from scratch as a pure-Python AES implementation.

**AES-256 primitive.** Standard tables-based implementation:
- `_SBOX` / `_INV_SBOX` (256 bytes each), `_RCON` (10 bytes).
- `_key_expansion(key)` → 15 × 16-byte round keys (Nk=8, Nr=14, Nb=4 for AES-256).
- `_aes_encrypt_block(block, rks)` and `_aes_decrypt_block(block, rks)` operating on 16-byte state via SubBytes / ShiftRows / MixColumns (and their inverses) plus AddRoundKey.
- MixColumns via the standard `xtime`-based GF(2^8) multiply.

**V1 — AES-256-CBC with OpenSSL's `EVP_BytesToKey`.** Ruby's `pkcs5_keyivgen(password, salt, 1, hash)` is `EVP_BytesToKey` with `count=1`:

```
D_0 = empty
D_i = hash(D_{i-1} || password || salt)    # no inner iteration when count=1
material = D_1 || D_2 || ...               # until ≥ 48 bytes
key = material[0:32]; iv = material[32:48]
```

CBC decrypt: per 16-byte block, inverse-cipher then XOR with previous ciphertext block (seed = `iv`). Strip PKCS#7 padding at the end (validate `1 ≤ pad ≤ 16` and all pad bytes equal). Try `md5` first; on failure (non-PKCS#7 tail or downstream error), retry with `sha256`, mirroring the Ruby `rescue` fallback.

**V2 — AES-256-GCM with PBKDF2-derived key + IV + AAD.** Key schedule matches Ruby exactly:

```
material = hashlib.pbkdf2_hmac('sha256', password, salt, 10_000, dklen=32+12+24)
key = material[0:32]; iv = material[32:44]; aad = material[44:68]
```

GCM decrypt (IV is 96-bit, the common case):
- `H = AES_encrypt(key, 0^128)`  (GHASH subkey)
- `J0 = iv || 0x00000001`
- Stream the ciphertext via CTR starting from `inc32(J0)`; counter is the low 32 bits of the block, rolled over mod 2^32.
- `GHASH(H, aad, ciphertext)` = fold AAD (zero-padded to 16), then ciphertext (zero-padded to 16), then `len(aad)_64 || len(ct)_64` bits, via GF(2^128) multiplication with reduction polynomial `0xe1…00`.
- `T = GHASH output XOR AES_encrypt(key, J0)`; raise if `T != auth_tag`.

GF(2^128) multiply is the standard right-shift-with-conditional-reduce loop (per-bit; fine for the kilobytes-at-most we're decrypting).

**File I/O.** The fastlane match file is ASCII base64 (confirmed on the live repo). Read as text, strip whitespace, base64-decode, dispatch on the 20-byte V2 magic prefix vs. the 8-byte `Salted__` V1 prefix. Replace the text-vs-binary heuristic in the current broken implementation — that heuristic was wrong and is unnecessary.

**Public API.** Keep `decrypt_match_data(source_path, destination_path, password)` signature so `BuildConfiguration.py` can swap the shell-out for a direct call with a one-line change.

## Changes

1. **Rewrite `build-system/Make/DecryptMatch.py`** end to end: AES primitives, `EVP_BytesToKey`, CBC decrypt, GCM decrypt, MatchDataEncryption dispatch, `decrypt_match_data` entry point. Drop the `subprocess`/`tempfile` and placeholder-V2 code paths entirely.
2. **Flip `BuildConfiguration.py:103-118`** — replace the `os.system('ruby build-system/decrypt.rb …')` call with `decrypt_match_data(source_path, destination_path, password)`. Remove the dead commented line.
3. **Delete `build-system/decrypt.rb`**.

## Verification

Run the user-supplied command:

```
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/build/telegram/telegram-bazel-cache \
  generateProject \
  --configurationPath ~/build/telegram/telegram-internal-tools/PrivateData/build-configurations/enterprise-configuration.json \
  --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
  --gitCodesigningType development --gitCodesigningUseCurrent
```

Success criteria: `generateProject` completes, the `decrypted/profiles/development/*.mobileprovision` files are valid plists parseable by `openssl smime` (which `copy_profiles_from_directory` does immediately after, so any decryption corruption would surface there), and the generated Xcode project has correct signing settings.

Cross-check during development: decrypt one sample file with both the old Ruby script and the new Python and compare `sha256sum`s byte-for-byte before running the full command.

## Non-goals

- V1 with salt-less files (the fastlane "no salt" format variant): the Ruby script doesn't handle it either.
- GCM with non-96-bit IV: PBKDF2 derivation fixes IV length at 12 bytes, so this case cannot arise.
- Streaming decryption for huge files: match files are at most a few MB.
- AES-128 / AES-192: unused by fastlane match.
