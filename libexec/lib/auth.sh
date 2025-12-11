#!/usr/bin/env bash
# ============================================================================
# bgs: auth.sh - Authentication module (QR login + cookie refresh)
# bgs = bilibili goods
# ============================================================================

# Get script directory
_AUTH_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load dependencies
# shellcheck disable=SC1091
source "${_AUTH_SCRIPT_DIR}/common.sh"
# shellcheck disable=SC1091
source "${_AUTH_SCRIPT_DIR}/crypto.sh"

# ============================================================================
# QR Code Login
# ============================================================================

# Generate login QR code
# Returns: qrcode_key
qr_generate() {
    local url="${BILI_PASSPORT}/x/passport-login/web/qrcode/generate"
    local resp
    
    resp=$(http_get "$url")
    
    local code
    code=$(echo "$resp" | jq -r '.code')
    
    if [[ "$code" != "0" ]]; then
        log_error "Failed to generate QR code: $resp"
        return 1
    fi
    
    local qrcode_key qrcode_url
    qrcode_key=$(echo "$resp" | jq -r '.data.qrcode_key')
    qrcode_url=$(echo "$resp" | jq -r '.data.url')
    
    # Display QR code
    echo ""
    log_info "Please scan the QR code with Bilibili app"
    echo ""
    
    if command -v qrencode &>/dev/null; then
        # Use qrencode to display QR code in terminal
        qrencode -t UTF8 -m 2 "$qrcode_url"
    else
        # No qrencode, show URL
        log_warn "qrencode not installed, please open this URL in browser:"
        echo ""
        echo "  $qrcode_url"
        echo ""
        log_info "Or install qrencode: brew install qrencode"
    fi
    
    echo ""
    echo "$qrcode_key"
}

# Poll QR code scan status
# Args: $1 = qrcode_key
# Returns: login response on success
qr_poll() {
    local qrcode_key="$1"
    local url="${BILI_PASSPORT}/x/passport-login/web/qrcode/poll?qrcode_key=${qrcode_key}"
    
    local max_attempts=60  # Wait up to 60 seconds
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        local resp
        resp=$(http_get "$url")
        
        local code
        code=$(echo "$resp" | jq -r '.data.code')
        
        case "$code" in
            0)
                # Login successful
                log_success "Login successful!"
                echo "$resp"
                return 0
                ;;
            86038)
                # QR code expired
                log_error "QR code expired. Please try again."
                return 1
                ;;
            86090)
                # Scanned, waiting for confirmation
                echo -ne "\r${YELLOW}[WAIT]${NC} Scanned, waiting for confirmation... "
                ;;
            86101)
                # Not scanned yet
                echo -ne "\r${CYAN}[WAIT]${NC} Waiting for scan... ($((max_attempts - attempt))s) "
                ;;
            *)
                log_error "Unknown status code: $code"
                log_debug "Response: $resp"
                ;;
        esac
        
        sleep 1
        ((attempt++))
    done
    
    echo ""
    log_error "Login timeout. Please try again."
    return 1
}

# Parse login response and extract auth info
# Args: $1 = qr_poll response
parse_login_response() {
    local resp="$1"
    
    # Extract refresh_token
    local refresh_token
    refresh_token=$(echo "$resp" | jq -r '.data.refresh_token')
    
    # Extract URL with cookie params
    local login_url
    login_url=$(echo "$resp" | jq -r '.data.url')
    
    # Parse cookie params from URL
    local sessdata bili_jct dede_user_id
    
    # URL format: https://passport.biligame.com/x/passport-login/web/crossDomain?DedeUserID=xxx&SESSDATA=xxx&bili_jct=xxx...
    sessdata=$(echo "$login_url" | grep -oE 'SESSDATA=[^&]+' | cut -d'=' -f2)
    bili_jct=$(echo "$login_url" | grep -oE 'bili_jct=[^&]+' | cut -d'=' -f2)
    dede_user_id=$(echo "$login_url" | grep -oE 'DedeUserID=[^&]+' | cut -d'=' -f2)
    
    # URL decode SESSDATA (may contain special characters)
    sessdata=$(printf '%b' "${sessdata//%/\\x}")
    
    if [[ -z "$sessdata" || -z "$refresh_token" || -z "$bili_jct" ]]; then
        log_error "Failed to parse login response"
        log_debug "URL: $login_url"
        return 1
    fi
    
    # Save auth info
    save_auth "$sessdata" "$refresh_token" "$bili_jct" "$dede_user_id"
    
    log_success "Auth saved to $BG_AUTH_FILE"
    echo ""
    echo "  User ID: $dede_user_id"
    echo ""
}

# Complete QR code login flow
do_qr_login() {
    log_info "Starting QR code login..."
    
    # Generate QR code
    local qrcode_key
    qrcode_key=$(qr_generate | tail -1)
    
    if [[ -z "$qrcode_key" ]]; then
        return 1
    fi
    
    # Poll status
    local login_resp
    login_resp=$(qr_poll "$qrcode_key")
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Parse and save
    parse_login_response "$login_resp"
}

# ============================================================================
# Cookie Refresh
# ============================================================================

# Check if cookie needs refresh
# Returns: 0 = needs refresh, 1 = no refresh needed
check_need_refresh() {
    load_auth || return 0  # No auth, need to login
    
    local cookie
    cookie=$(build_cookie)
    
    local url="${BILI_PASSPORT}/x/passport-login/web/cookie/info?csrf=${BILI_JCT}"
    local resp
    
    resp=$(http_get "$url" "$cookie")
    
    local code
    code=$(echo "$resp" | jq -r '.code')
    
    if [[ "$code" != "0" ]]; then
        log_debug "check_need_refresh failed: $resp"
        return 0  # Error, try refresh
    fi
    
    local refresh
    refresh=$(echo "$resp" | jq -r '.data.refresh')
    
    if [[ "$refresh" == "true" ]]; then
        return 0  # Needs refresh
    fi
    
    return 1  # No refresh needed
}

# Get refresh_csrf
# Args: $1 = correspondPath
get_refresh_csrf() {
    local correspond_path="$1"
    
    load_auth || return 1
    
    local cookie
    cookie=$(build_cookie)
    
    local url="${BILI_WWW}/correspond/1/${correspond_path}"
    local resp
    
    resp=$(http_get "$url" "$cookie")
    
    # Extract refresh_csrf from HTML
    # <div id="1-name">xxxxx</div>
    local refresh_csrf
    refresh_csrf=$(echo "$resp" | grep -oP '(?<=<div id="1-name">)[^<]+' || \
                   echo "$resp" | sed -n 's/.*<div id="1-name">\([^<]*\)<\/div>.*/\1/p')
    
    if [[ -z "$refresh_csrf" ]]; then
        log_error "Failed to get refresh_csrf"
        log_debug "Response: $resp"
        return 1
    fi
    
    echo "$refresh_csrf"
}

# Refresh cookie
# Args: $1 = refresh_csrf
do_refresh_cookie() {
    local refresh_csrf="$1"
    
    load_auth || return 1
    
    local cookie
    cookie=$(build_cookie)
    
    local url="${BILI_PASSPORT}/x/passport-login/web/cookie/refresh"
    
    # Create temp file for response headers
    local header_file
    header_file=$(mktemp)
    
    local resp
    resp=$(curl -s -A "$UA" \
        -H "cookie: $cookie" \
        -X POST "$url" \
        --data-urlencode "csrf=${BILI_JCT}" \
        --data-urlencode "refresh_csrf=${refresh_csrf}" \
        --data-urlencode "source=main_web" \
        --data-urlencode "refresh_token=${REFRESH_TOKEN}" \
        -D "$header_file")
    
    local code
    code=$(echo "$resp" | jq -r '.code')
    
    if [[ "$code" != "0" ]]; then
        log_error "Cookie refresh failed: $resp"
        rm -f "$header_file"
        return 1
    fi
    
    # Extract new refresh_token
    local new_refresh_token
    new_refresh_token=$(echo "$resp" | jq -r '.data.refresh_token')
    
    # Extract new cookies from response headers
    local new_sessdata new_bili_jct new_dede_user_id
    
    new_sessdata=$(grep -i "Set-Cookie.*SESSDATA=" "$header_file" | \
                   sed 's/.*SESSDATA=\([^;]*\).*/\1/' | head -1)
    new_bili_jct=$(grep -i "Set-Cookie.*bili_jct=" "$header_file" | \
                   sed 's/.*bili_jct=\([^;]*\).*/\1/' | head -1)
    new_dede_user_id=$(grep -i "Set-Cookie.*DedeUserID=" "$header_file" | \
                       sed 's/.*DedeUserID=\([^;]*\).*/\1/' | head -1)
    
    rm -f "$header_file"
    
    # Keep old values if new ones are empty
    new_sessdata="${new_sessdata:-$SESSDATA}"
    new_bili_jct="${new_bili_jct:-$BILI_JCT}"
    new_dede_user_id="${new_dede_user_id:-$DEDE_USER_ID}"
    
    # Save new auth info
    save_auth "$new_sessdata" "$new_refresh_token" "$new_bili_jct" "$new_dede_user_id"
    
    log_success "Cookie refreshed successfully"
    return 0
}

# Confirm refresh (invalidate old token)
# Args: $1 = old refresh_token
confirm_refresh() {
    local old_refresh_token="$1"
    
    load_auth || return 1
    
    local cookie
    cookie=$(build_cookie)
    
    local url="${BILI_PASSPORT}/x/passport-login/web/confirm/refresh"
    local resp
    
    resp=$(curl -s -A "$UA" \
        -H "cookie: $cookie" \
        -X POST "$url" \
        --data-urlencode "csrf=${BILI_JCT}" \
        --data-urlencode "refresh_token=${old_refresh_token}")
    
    local code
    code=$(echo "$resp" | jq -r '.code')
    
    if [[ "$code" != "0" ]]; then
        log_warn "confirm_refresh returned code=$code (this is usually ok)"
        log_debug "Response: $resp"
    fi
    
    return 0
}

# Complete cookie refresh flow
do_cookie_refresh() {
    log_info "Checking cookie status..."
    
    if ! check_need_refresh; then
        log_success "Cookie is still valid, no refresh needed"
        return 0
    fi
    
    log_info "Cookie needs refresh, starting refresh process..."
    
    # Save old refresh_token
    load_auth
    local old_refresh_token="$REFRESH_TOKEN"
    
    # Get timestamp
    local timestamp
    timestamp=$(get_timestamp_ms)
    log_debug "Timestamp: $timestamp"
    
    # Generate correspondPath
    local correspond_path
    correspond_path=$(generate_correspond_path "$timestamp")
    
    if [[ -z "$correspond_path" ]]; then
        log_error "Failed to generate correspondPath"
        return 1
    fi
    
    log_debug "CorrespondPath: $correspond_path"
    
    # Get refresh_csrf
    local refresh_csrf
    refresh_csrf=$(get_refresh_csrf "$correspond_path")
    
    if [[ -z "$refresh_csrf" ]]; then
        log_error "Failed to get refresh_csrf"
        return 1
    fi
    
    log_debug "RefreshCSRF: $refresh_csrf"
    
    # Refresh cookie
    if ! do_refresh_cookie "$refresh_csrf"; then
        log_error "Cookie refresh failed"
        return 1
    fi
    
    # Confirm refresh
    confirm_refresh "$old_refresh_token"
    
    return 0
}

# ============================================================================
# Main entry point - ensure auth is valid
# Call this before executing any command
# ============================================================================
ensure_auth() {
    # Check if logged in
    if ! is_logged_in; then
        log_warn "Not logged in. Starting QR code login..."
        echo ""
        if ! do_qr_login; then
            log_error "Login failed. Please try again."
            exit 1
        fi
    fi
    
    # Try to refresh cookie
    if ! do_cookie_refresh; then
        log_warn "Cookie refresh failed. You may need to re-login."
        log_info "Use 'bgs auth login' to re-login."
        
        # Ask if user wants to re-login
        echo ""
        read -p "Do you want to re-login now? [y/N] " -n 1 -r
        echo ""
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Clear old auth
            rm -f "$BG_AUTH_FILE"
            if ! do_qr_login; then
                log_error "Login failed. Please try again."
                exit 1
            fi
        else
            exit 1
        fi
    fi
}
