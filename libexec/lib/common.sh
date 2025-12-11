#!/usr/bin/env bash
# ============================================================================
# bgs: common.sh - Shared variables and functions
# bgs = bilibili goods
# ============================================================================

# Version
BG_VERSION="1.0.0"

# Config directory and files
BG_HOME="${HOME}/.bg-cmd"
BG_AUTH_FILE="${BG_HOME}/auth"
BG_CONFIG_FILE="${BG_HOME}/config"

# API base URLs
BILI_PASSPORT="https://passport.bilibili.com"
BILI_MALL="https://mall.bilibili.com"
BILI_PAY="https://pay.bilibili.com"
BILI_WWW="https://www.bilibili.com"

# User-Agent
UA="Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# Logging functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_debug() {
    if [[ "${BG_DEBUG:-}" == "1" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $*"
    fi
}

# ============================================================================
# Initialization functions
# ============================================================================

# Ensure config directory exists
ensure_bg_home() {
    if [[ ! -d "$BG_HOME" ]]; then
        mkdir -p "$BG_HOME"
        chmod 700 "$BG_HOME"
    fi
}

# Check dependencies
check_dependencies() {
    local missing=()
    
    # Required dependencies
    for cmd in curl jq openssl qrencode; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        log_error "Please install them with: brew install ${missing[*]}"
        exit 1
    fi
}

# ============================================================================
# Authentication functions
# ============================================================================

# Load auth info from file
load_auth() {
    if [[ -f "$BG_AUTH_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$BG_AUTH_FILE"
        return 0
    fi
    return 1
}

# Save auth info to file
save_auth() {
    local sessdata="$1"
    local refresh_token="$2"
    local bili_jct="$3"
    local dede_user_id="$4"
    
    ensure_bg_home
    
    cat > "$BG_AUTH_FILE" << EOF
# bg-cmd auth file - DO NOT EDIT MANUALLY
# Generated at: $(date '+%Y-%m-%d %H:%M:%S')
SESSDATA="$sessdata"
REFRESH_TOKEN="$refresh_token"
BILI_JCT="$bili_jct"
DEDE_USER_ID="$dede_user_id"
EOF
    
    chmod 600 "$BG_AUTH_FILE"
}

# Check if user is logged in
is_logged_in() {
    if [[ -f "$BG_AUTH_FILE" ]]; then
        load_auth
        if [[ -n "${SESSDATA:-}" && -n "${REFRESH_TOKEN:-}" ]]; then
            return 0
        fi
    fi
    return 1
}

# Build cookie string for HTTP requests
# SESSDATA is already URL-encoded when saved
build_cookie() {
    load_auth || return 1
    echo "SESSDATA=${SESSDATA}; bili_jct=${BILI_JCT}; DedeUserID=${DEDE_USER_ID}"
}

# ============================================================================
# Configuration functions
# ============================================================================

# Read config value
config_get() {
    local key="$1"
    local default="${2:-}"
    
    if [[ -f "$BG_CONFIG_FILE" ]]; then
        local value
        # Use grep -F for fixed string matching (key may contain dots)
        value=$(grep -F "${key}=" "$BG_CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/^"//;s/"$//')
        if [[ -n "$value" ]]; then
            echo "$value"
            return 0
        fi
    fi
    
    echo "$default"
}

# Write config value
config_set() {
    local key="$1"
    local value="$2"
    
    ensure_bg_home
    
    # Create config file if not exists
    if [[ ! -f "$BG_CONFIG_FILE" ]]; then
        touch "$BG_CONFIG_FILE"
    fi
    
    # Remove old config line (use fixed string matching)
    if grep -qF "${key}=" "$BG_CONFIG_FILE" 2>/dev/null; then
        # macOS and Linux compatible sed
        local tmp_file="${BG_CONFIG_FILE}.tmp"
        grep -vF "${key}=" "$BG_CONFIG_FILE" > "$tmp_file" || true
        mv "$tmp_file" "$BG_CONFIG_FILE"
    fi
    
    # Add new config
    echo "${key}=\"${value}\"" >> "$BG_CONFIG_FILE"
}

# Remove config value
config_unset() {
    local key="$1"
    
    if [[ -f "$BG_CONFIG_FILE" ]]; then
        local tmp_file="${BG_CONFIG_FILE}.tmp"
        grep -vF "${key}=" "$BG_CONFIG_FILE" > "$tmp_file" || true
        mv "$tmp_file" "$BG_CONFIG_FILE"
    fi
}

# List all configs
config_list() {
    if [[ -f "$BG_CONFIG_FILE" ]]; then
        cat "$BG_CONFIG_FILE"
    else
        echo "No configuration found."
    fi
}

# ============================================================================
# Price functions
# ============================================================================

# Parse price config
# Returns: "fixed:price" or "random:min:max" (unit: yuan, same as API)
parse_price_config() {
    local price_config
    price_config=$(config_get "publish.price" "200")
    
    # Check if it's array format [min, max]
    if [[ "$price_config" =~ ^\[([0-9]+),\ *([0-9]+)\]$ ]]; then
        local min_yuan="${BASH_REMATCH[1]}"
        local max_yuan="${BASH_REMATCH[2]}"
        echo "random:${min_yuan}:${max_yuan}"
    else
        echo "fixed:${price_config}"
    fi
}

# Calculate actual publish price
# Args: $1 = item max price (fen, from API)
# Returns: actual price (yuan, for API input)
calculate_price() {
    local max_price_fen="$1"
    # Convert max price from fen to yuan for comparison
    local max_price_yuan=$((max_price_fen / 100))
    
    local price_info
    price_info=$(parse_price_config)
    
    local mode="${price_info%%:*}"
    local price
    
    if [[ "$mode" == "fixed" ]]; then
        price="${price_info#fixed:}"
    else
        # random:min:max
        local rest="${price_info#random:}"
        local min="${rest%%:*}"
        local max="${rest#*:}"
        # Generate random price in range
        price=$((RANDOM % (max - min + 1) + min))
    fi
    
    # Use min of user price and item max price (both in yuan)
    if [[ "$price" -gt "$max_price_yuan" ]]; then
        price="$max_price_yuan"
    fi
    
    echo "$price"
}

# ============================================================================
# HTTP request helper functions
# ============================================================================

# Send GET request
http_get() {
    local url="$1"
    local cookie="${2:-}"
    
    local args=(-s -A "$UA" --connect-timeout 10 --max-time 30)
    if [[ -n "$cookie" ]]; then
        args+=(-H "cookie: $cookie")
    fi
    
    curl "${args[@]}" "$url"
}

# Send POST request (JSON body)
http_post_json() {
    local url="$1"
    local data="$2"
    local cookie="${3:-}"
    
    local args=(-s -A "$UA" -X POST -H "content-type: application/json" --connect-timeout 10 --max-time 30)
    if [[ -n "$cookie" ]]; then
        args+=(-H "cookie: $cookie")
    fi
    
    curl "${args[@]}" --data "$data" "$url"
}

# Send POST request (Form data)
http_post_form() {
    local url="$1"
    shift
    local cookie=""
    local data_args=()
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cookie)
                cookie="$2"
                shift 2
                ;;
            *)
                data_args+=(--data-urlencode "$1")
                shift
                ;;
        esac
    done
    
    local args=(-s -A "$UA" -X POST)
    if [[ -n "$cookie" ]]; then
        args+=(-H "cookie: $cookie")
    fi
    
    curl "${args[@]}" "${data_args[@]}" "$url"
}
