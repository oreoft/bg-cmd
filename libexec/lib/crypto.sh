#!/usr/bin/env bash
# ============================================================================
# bgs: crypto.sh - RSA-OAEP encryption module (for cookie refresh)
# bgs = bilibili goods
# ============================================================================

# RSA public key (PEM format) - used to generate correspondPath
# Source: https://github.com/SocialSisterYi/bilibili-API-collect
RSA_PUBKEY_PEM="-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDLgd2OAkcGVtoE3ThUREbio0Eg
Uc/prcajMKXvkCKFCWhJYJcLkcM2DKKcSeFpD/j6Boy538YXnR6VhcuUJOhH2x71
nzPjfdTcqMz7djHum0qSZA0AyCBDABUqCrfNgCiJ00Ra7GmRj+YCK1NJEuewlb40
JNrRuoEUXpabUzGB8QIDAQAB
-----END PUBLIC KEY-----"

# ============================================================================
# Generate correspondPath
# Encrypt "refresh_${timestamp}" using RSA-OAEP
# Args: $1 = millisecond timestamp
# Returns: hex-encoded ciphertext
# ============================================================================
generate_correspond_path() {
    local timestamp="$1"
    local plaintext="refresh_${timestamp}"
    
    # Use openssl for RSA-OAEP encryption
    # Note: macOS default openssl (LibreSSL) may not support -pkeyopt
    # May need Homebrew installed openssl
    
    local encrypted
    
    # Try using openssl pkeyutl (requires OpenSSL 1.0+)
    if encrypted=$(echo -n "$plaintext" | \
        openssl pkeyutl -encrypt \
            -pubin -inkey <(echo "$RSA_PUBKEY_PEM") \
            -pkeyopt rsa_padding_mode:oaep \
            -pkeyopt rsa_oaep_md:sha256 \
            2>/dev/null | xxd -p -c 256 | tr -d '\n'); then
        echo "$encrypted"
        return 0
    fi
    
    # If openssl doesn't work, try Python
    if command -v python3 &>/dev/null; then
        encrypted=$(python3 << PYTHON_SCRIPT
from Crypto.Cipher import PKCS1_OAEP
from Crypto.PublicKey import RSA
from Crypto.Hash import SHA256
import binascii

pubkey_pem = """$RSA_PUBKEY_PEM"""
key = RSA.import_key(pubkey_pem)
cipher = PKCS1_OAEP.new(key, hashAlgo=SHA256)
plaintext = b"$plaintext"
encrypted = cipher.encrypt(plaintext)
print(binascii.hexlify(encrypted).decode())
PYTHON_SCRIPT
        )
        if [[ $? -eq 0 && -n "$encrypted" ]]; then
            echo "$encrypted"
            return 0
        fi
    fi
    
    # Both methods failed
    log_error "Failed to generate correspondPath. Please ensure openssl or python3 with pycryptodome is installed."
    return 1
}

# ============================================================================
# Get current millisecond timestamp
# ============================================================================
get_timestamp_ms() {
    # macOS date doesn't support %N, use python or perl
    if command -v python3 &>/dev/null; then
        python3 -c "import time; print(int(time.time() * 1000))"
    elif command -v perl &>/dev/null; then
        perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'
    else
        # Fallback: use seconds * 1000
        echo "$(($(date +%s) * 1000))"
    fi
}
