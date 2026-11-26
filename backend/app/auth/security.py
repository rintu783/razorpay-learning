from pwdlib import PasswordHash

# Argon2id with the library's recommended defaults. It is memory-hard, which makes
# offline brute-force of a leaked hash expensive. The salt is generated per password and
# stored inside the hash string.
_hasher = PasswordHash.recommended()

# Verified against when the email does not exist, so a login for an unknown email takes
# about as long as one for a known email (prevents account enumeration by timing).
_DUMMY_HASH = _hasher.hash("not-a-real-password")


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str | None) -> bool:
    """Return True if the password matches. With password_hash=None, burns equal time and returns False."""
    if password_hash is None:
        _hasher.verify(password, _DUMMY_HASH)
        return False
    return _hasher.verify(password, password_hash)
