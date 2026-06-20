# 0001 — Validate module signatures in the secure plane with plane-local keys

- **Status:** Open
- **Area:** secure-plane key custody / module authentication
- **Depends on:** `VBS_CALL_VALIDATE_MODULE`, `VBS_CALL_ADD_KEY`, `VBS_CALL_REVOKE_KEY`, `VBS_CALL_SEND_CERTS`
- **Relates to:** module loading path, kernel keyrings

## Goal

Perform **all** kernel module signature validation inside the secure kernel
(plane 1), using keys that live **only** in that plane. The normal plane
(plane 0) must not hold the trust roots used to authorize code, and must not be
able to read any private key material.

This makes the secure plane the sole authority for "may this module run", so a
compromised plane 0 cannot add a trust root, forge a verification result, or
exfiltrate private keys.

## Requirements (from the request)

1. **Migrate trust roots to plane 1 at boot.** Before plane 0 loads any module
   or starts userspace, move the keys from plane 0's kernel keyrings to the
   secure plane. After migration, plane 0 retains no copy of the trust roots
   used for module authentication.
2. **Validate entirely in plane 1.** Module signature verification runs in the
   secure kernel against its local keys; plane 0 only forwards the module image
   + signature and receives an allow/deny verdict.
3. **Route key additions to plane 1.** Any key added on plane 0 after boot is
   forwarded to the secure plane rather than stored locally.
4. **Private-key confidentiality.** Once a key is held by the secure kernel,
   plane 0 can read the **public** half (e.g. to display certs / key IDs) but can
   never read the **private** half.

## Background (kernel specifics)

- Module verification today calls `mod_verify_sig()`
  ([kernel/module/signing.c](../../../linux/kernel/module/signing.c)) →
  `verify_pkcs7_signature(..., VERIFY_USE_SECONDARY_KEYRING, ...)`, checking the
  signature against the builtin + secondary trusted keyrings (and `.machine`).
- For *module signing*, the kernel keyring normally holds only the **public**
  certificate; the private signing key lives off-box. So for that path, "move
  the keys" means moving the **verification trust roots** into plane 1 and doing
  the PKCS#7 verification there.
- The broader requirement (private keys visible only to plane 1) applies to key
  types that *do* carry secret material in-kernel — asymmetric keys with a
  private half, `trusted`/`encrypted` keys, IMA/EVM keys, and user/session
  keyring secrets. These are the keys whose private bytes must never be
  reachable from plane 0.

## Proposal

### A. Boot-time keyring migration
- Before plane 0 enables module loading / `init`, enumerate the relevant
  keyrings (builtin/secondary/`.machine`/`.platform`, plus any private-bearing
  keys) and hand them to the secure plane via `VBS_CALL_SEND_CERTS` /
  `VBS_CALL_ADD_KEY`.
- The secure plane imports them into its own plane-local keyrings.
- Plane 0 then **drops** the trust roots / private material it just exported, so
  it cannot authorize code or leak secrets afterward.
- Ordering is critical: migration must complete *before* the first module load
  and before userspace starts (ties to the boot-sequence watershed; see #0006).

### B. Mediated verification
- Re-point the plane-0 module path so `mod_verify_sig()` (or its caller)
  forwards `(module image, PKCS#7 signature)` to the secure plane via
  `VBS_CALL_VALIDATE_MODULE` and acts on the returned verdict.
- The secure plane performs the actual PKCS#7 verification against its local
  keyrings and returns allow/deny (no key material crosses the boundary).

### C. Route runtime key additions to plane 1
- Intercept plane-0 key-add entry points (`add_key(2)` / `keyctl` / in-kernel
  `key_create_or_update`) for the in-scope keyrings and forward to the secure
  plane via `VBS_CALL_ADD_KEY`; mirror revocation via `VBS_CALL_REVOKE_KEY`.
- Decide policy for keys that plane 0 is *not* allowed to add at all (reject vs.
  forward), and which keyrings are in scope.

### D. Public-only view in plane 0
- For keys held in plane 1, expose a **read-only public** projection to plane 0
  (public key / certificate / key ID / description) so existing userspace and
  `keyctl` reads still work for public data.
- Private/secret bytes are never returned across the boundary; a plane-0 read of
  private material returns an error (e.g. `-EACCES`/`-ENOKEY`).

## Acceptance criteria

- [ ] After boot, plane 0 holds no module-authentication trust roots; the
      builtin/secondary/`.machine` trust used for verification lives in plane 1.
- [ ] A correctly signed module loads on plane 0; the allow/deny decision is
      produced by the secure plane (verifiable in secure-plane logs).
- [ ] A module signed by a key only plane 0 tried to add (post-boot, not honored
      by plane 1) is **rejected**.
- [ ] A key added on plane 0 after boot appears in plane 1; its public half is
      readable from plane 0, its private half is not.
- [ ] No private key bytes are ever transferred from plane 1 to plane 0.

## Open questions

- Exact set of keyrings in scope (builtin/secondary/`.machine`/`.platform`/
  `.blacklist`, user/session keyrings, IMA/EVM, trusted/encrypted).
- Wire format for the public-only projection exposed to plane 0.
- Whether plane 0 may add keys at all post-boot, or only request plane-1-side
  additions subject to secure-plane policy.
- Interaction with measured boot / attestation of the migrated trust roots.
