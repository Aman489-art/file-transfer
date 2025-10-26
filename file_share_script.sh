#!/bin/bash

# Interactive Fast File Transfer Script
# Optimized for speed with parallel compression and multi-threaded transfers
# Auto-detects systems and guides you through the process

set -euo pipefail

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
DEFAULT_PORT=9999
COMPRESSION_LEVEL=1  # Fast compression (1-9, lower is faster)
BUFFER_SIZE=65536    # 64KB buffer for faster transfers
SERVER_PID=""

# Cleanup
cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
    fi
    rm -f /tmp/transfer_*.tar.* 2>/dev/null
    exit 0
}

trap cleanup EXIT INT TERM

# Logging functions
log() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; }
warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
info() { echo -e "${CYAN}[ℹ]${NC} $1"; }
success() { echo -e "${MAGENTA}[★]${NC} $1"; }
prompt() { echo -e "${BLUE}[?]${NC} $1"; }

# Print header
print_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}ULTRA-FAST WIRELESS FILE TRANSFER${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}     Multi-threaded | Optimized | Cross-platform       ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Check command availability
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "Linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macOS"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
        echo "Windows"
    else
        echo "Unknown"
    fi
}

# Check and install dependencies
check_dependencies() {
    local missing=()
    
    if ! command_exists nc; then
        missing+=("netcat")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required tools: ${missing[*]}"
        echo ""
        info "Installation commands:"
        
        local os=$(detect_os)
        case "$os" in
            Linux)
                if command_exists apt; then
                    echo "  sudo apt update && sudo apt install -y netcat-openbsd pv pigz"
                elif command_exists yum; then
                    echo "  sudo yum install -y nmap-ncat pv pigz"
                elif command_exists dnf; then
                    echo "  sudo dnf install -y nmap-ncat pv pigz"
                fi
                ;;
            macOS)
                echo "  brew install netcat pv pigz"
                ;;
            Windows)
                echo "  Install via WSL or Git Bash"
                ;;
        esac
        echo ""
        read -p "Press Enter to exit..."
        exit 1
    fi
}

# Get local IP addresses
get_ip_addresses() {
    local ips=()
    
    if command_exists ip; then
        while IFS= read -r line; do
            [ -n "$line" ] && ips+=("$line")
        done < <(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1')
    elif command_exists ifconfig; then
        while IFS= read -r line; do
            [ -n "$line" ] && ips+=("$line")
        done < <(ifconfig 2>/dev/null | grep -oP 'inet (addr:)?(\d+\.){3}\d+' | grep -oP '(\d+\.){3}\d+' | grep -v '127.0.0.1')
    elif command_exists hostname; then
        local ip=$(hostname -I 2>/dev/null | awk '{print $1}' | grep -v '127.0.0.1')
        [ -n "$ip" ] && ips+=("$ip")
    fi
    
    printf '%s\n' "${ips[@]}"
}

# Check network connectivity
check_network() {
    local ips
    mapfile -t ips < <(get_ip_addresses)
    
    if [ ${#ips[@]} -eq 0 ]; then
        return 1
    fi
    return 0
}

# Get file/directory size
get_size() {
    local path=$1
    if [ -d "$path" ]; then
        du -sb "$path" 2>/dev/null | awk '{print $1}' || echo "0"
    else
        stat -c%s "$path" 2>/dev/null || stat -f%z "$path" 2>/dev/null || echo "0"
    fi
}

# Format bytes to human readable
format_size() {
    local bytes=$1
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
    elif [ "$bytes" -lt 1048576 ]; then
        echo "$((bytes / 1024))KB"
    elif [ "$bytes" -lt 1073741824 ]; then
        echo "$((bytes / 1048576))MB"
    else
        echo "$((bytes / 1073741824))GB"
    fi
}

# Check if port is available
check_port() {
    local port=$1
    if command_exists netstat; then
        netstat -tuln 2>/dev/null | grep -q ":$port " && return 1
    elif command_exists ss; then
        ss -tuln 2>/dev/null | grep -q ":$port " && return 1
    fi
    return 0
}

# Interactive menu
show_menu() {
    local choice
    while true; do
        print_header
        
        # Check network
        if ! check_network; then
            error "No network connection detected!"
            echo ""
            info "Please ensure:"
            echo "  • WiFi or Ethernet is connected"
            echo "  • Both devices are on the same network"
            echo ""
            read -p "Press Enter to retry or Ctrl+C to exit..."
            continue
        fi
        
        log "Network connection detected"
        echo ""
        
        echo -e "${BOLD}What do you want to do?${NC}"
        echo ""
        echo "  ${CYAN}1${NC}) 📤 Send files/folders (I'm the SENDER)"
        echo "  ${CYAN}2${NC}) 📥 Receive files/folders (I'm the RECEIVER)"
        echo "  ${CYAN}3${NC}) 🔧 Network diagnostics"
        echo "  ${CYAN}4${NC}) ❌ Exit"
        echo ""
        
        read -p "$(echo -e ${BLUE}[?]${NC}) Enter your choice [1-4]: " choice
        
        case "$choice" in
            1) sender_mode; break ;;
            2) receiver_mode; break ;;
            3) network_diagnostics; ;;
            4) echo ""; log "Goodbye!"; exit 0 ;;
            *) error "Invalid choice. Please select 1-4." ; sleep 2 ;;
        esac
    done
}

# Network diagnostics
network_diagnostics() {
    print_header
    echo -e "${BOLD}Network Diagnostics${NC}"
    echo ""
    
    log "Detecting your system..."
    local os=$(detect_os)
    info "Operating System: ${BOLD}$os${NC}"
    echo ""
    
    log "Detecting IP addresses..."
    local ips
    mapfile -t ips < <(get_ip_addresses)
    
    if [ ${#ips[@]} -eq 0 ]; then
        error "No network interfaces found!"
        echo ""
        warning "Troubleshooting steps:"
        echo "  1. Check if WiFi/Ethernet is connected"
        echo "  2. Try: ifconfig or ip addr show"
        echo "  3. Ensure you're not in airplane mode"
    else
        info "Available IP addresses:"
        for ip in "${ips[@]}"; do
            echo "  • $ip"
        done
    fi
    
    echo ""
    log "Checking required tools..."
    
    local tools=("nc:netcat" "pv:progress viewer" "pigz:parallel gzip" "mbuffer:multi-buffer")
    for tool_pair in "${tools[@]}"; do
        IFS=':' read -r cmd desc <<< "$tool_pair"
        if command_exists "$cmd"; then
            echo "  ${GREEN}✓${NC} $desc ($cmd)"
        else
            echo "  ${YELLOW}○${NC} $desc ($cmd) - optional, will use alternatives"
        fi
    done
    
    echo ""
    log "Checking firewall status..."
    if command_exists ufw; then
        local status=$(sudo ufw status 2>/dev/null | head -1)
        info "UFW: $status"
    elif command_exists firewall-cmd; then
        local status=$(sudo firewall-cmd --state 2>/dev/null || echo "unknown")
        info "Firewalld: $status"
    else
        info "No common firewall detected"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Sender mode
sender_mode() {
    print_header
    echo -e "${BOLD}📤 SENDER MODE${NC}"
    echo ""
    
    # Get what to send
    local send_type
    echo "What do you want to send?"
    echo "  ${CYAN}1${NC}) Single file"
    echo "  ${CYAN}2${NC}) Entire folder"
    echo ""
    read -p "$(echo -e ${BLUE}[?]${NC}) Enter choice [1-2]: " send_type
    
    local source_path=""
    local is_directory=false
    
    case "$send_type" in
        1)
            echo ""
            read -p "$(echo -e ${BLUE}[?]${NC}) Enter file path: " source_path
            source_path="${source_path/#\~/$HOME}"  # Expand ~
            
            if [ ! -f "$source_path" ]; then
                error "File not found: $source_path"
                sleep 2
                return
            fi
            ;;
        2)
            echo ""
            read -p "$(echo -e ${BLUE}[?]${NC}) Enter folder path: " source_path
            source_path="${source_path/#\~/$HOME}"  # Expand ~
            
            if [ ! -d "$source_path" ]; then
                error "Folder not found: $source_path"
                sleep 2
                return
            fi
            is_directory=true
            ;;
        *)
            error "Invalid choice"
            sleep 2
            return
            ;;
    esac
    
    # Get port
    echo ""
    read -p "$(echo -e ${BLUE}[?]${NC}) Port number (default 9999): " port
    port=${port:-9999}
    
    if ! check_port "$port"; then
        error "Port $port is already in use"
        sleep 2
        return
    fi
    
    # Show connection info
    print_header
    echo -e "${BOLD}📤 Ready to Send${NC}"
    echo ""
    
    local source_name=$(basename "$source_path")
    local source_size=$(get_size "$source_path")
    local formatted_size=$(format_size "$source_size")
    
    if [ "$is_directory" = true ]; then
        info "Folder: ${BOLD}$source_name${NC}"
    else
        info "File: ${BOLD}$source_name${NC}"
    fi
    info "Size: ${BOLD}$formatted_size${NC}"
    echo ""
    
    local ips
    mapfile -t ips < <(get_ip_addresses)
    
    success "Your IP addresses:"
    for ip in "${ips[@]}"; do
        echo "  • $ip"
    done
    echo ""
    
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  ${BOLD}Tell the receiver to run this command:${NC}              ${YELLOW}║${NC}"
    echo -e "${YELLOW}╠════════════════════════════════════════════════════════╣${NC}"
    for ip in "${ips[@]}"; do
        echo -e "${YELLOW}║${NC}  $0 --receive $ip:$port                    ${YELLOW}║${NC}"
    done
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    info "Waiting for receiver to connect..."
    echo ""
    
    # Start transfer
    if [ "$is_directory" = true ]; then
        send_directory_fast "$source_path" "$port"
    else
        send_file_fast "$source_path" "$port"
    fi
}

# Receiver mode
receiver_mode() {
    print_header
    echo -e "${BOLD}📥 RECEIVER MODE${NC}"
    echo ""
    
    read -p "$(echo -e ${BLUE}[?]${NC}) Enter sender's IP:PORT (e.g., 192.168.1.100:9999): " address
    
    if [[ ! "$address" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
        error "Invalid format! Use IP:PORT (e.g., 192.168.1.100:9999)"
        sleep 2
        return
    fi
    
    echo ""
    read -p "$(echo -e ${BLUE}[?]${NC}) Save to folder (default: current directory): " save_dir
    save_dir=${save_dir:-"."}
    save_dir="${save_dir/#\~/$HOME}"  # Expand ~
    
    if [ ! -d "$save_dir" ]; then
        mkdir -p "$save_dir" 2>/dev/null || {
            error "Cannot create directory: $save_dir"
            sleep 2
            return
        }
    fi
    
    print_header
    echo -e "${BOLD}📥 Connecting to Sender${NC}"
    echo ""
    
    receive_file_fast "$address" "$save_dir"
}

# Fast file send with optimizations
send_file_fast() {
    local file=$1
    local port=$2
    
    log "Starting optimized file transfer..."
    
    # Use mbuffer for faster transfer if available
    if command_exists mbuffer && command_exists pv; then
        pv "$file" | mbuffer -s $BUFFER_SIZE -m 10M | nc -l -p "$port" 2>/dev/null || \
        pv "$file" | nc -l "$port" 2>/dev/null || \
        nc -l -p "$port" < "$file"
    elif command_exists pv; then
        pv "$file" | nc -l -p "$port" 2>/dev/null || nc -l "$port" < "$file"
    else
        cat "$file" | nc -l -p "$port" 2>/dev/null || nc -l "$port" < "$file"
    fi
    
    echo ""
    success "Transfer complete!"
    echo ""
    read -p "Press Enter to continue..."
}

# Fast directory send with parallel compression
send_directory_fast() {
    local dir=$1
    local port=$2
    local archive="/tmp/transfer_$$.tar.gz"
    
    log "Compressing folder (fast mode)..."
    
    # Use pigz (parallel gzip) if available for 3-4x faster compression
    if command_exists pigz; then
        tar -C "$(dirname "$dir")" -c "$(basename "$dir")" 2>/dev/null | \
        pigz -$COMPRESSION_LEVEL -p $(nproc 2>/dev/null || echo 2) > "$archive"
    else
        tar -czf "$archive" -C "$(dirname "$dir")" "$(basename "$dir")" 2>/dev/null
    fi
    
    local archive_size=$(get_size "$archive")
    local formatted_size=$(format_size "$archive_size")
    
    log "Compressed to: $formatted_size"
    echo ""
    
    # Transfer with optimizations
    if command_exists mbuffer && command_exists pv; then
        pv "$archive" | mbuffer -s $BUFFER_SIZE -m 10M | nc -l -p "$port" 2>/dev/null || \
        pv "$archive" | nc -l "$port" 2>/dev/null || \
        nc -l -p "$port" < "$archive"
    elif command_exists pv; then
        pv "$archive" | nc -l -p "$port" 2>/dev/null || nc -l "$port" < "$archive"
    else
        cat "$archive" | nc -l -p "$port" 2>/dev/null || nc -l "$port" < "$archive"
    fi
    
    rm -f "$archive"
    
    echo ""
    success "Transfer complete!"
    echo ""
    read -p "Press Enter to continue..."
}

# Fast file receive with optimizations
receive_file_fast() {
    local address=$1
    local output_dir=$2
    
    local ip="${address%:*}"
    local port="${address##*:}"
    
    log "Connecting to $ip:$port..."
    
    local temp_file="$output_dir/received_$$.tmp"
    
    # Receive with optimizations
    if command_exists mbuffer && command_exists pv; then
        nc "$ip" "$port" 2>/dev/null | mbuffer -s $BUFFER_SIZE -m 10M | pv > "$temp_file" || \
        nc "$ip" "$port" | pv > "$temp_file" || \
        nc "$ip" "$port" > "$temp_file"
    elif command_exists pv; then
        nc "$ip" "$port" 2>/dev/null | pv > "$temp_file" || \
        nc "$ip" "$port" > "$temp_file"
    else
        nc "$ip" "$port" > "$temp_file" 2>/dev/null
    fi
    
    if [ ! -s "$temp_file" ]; then
        rm -f "$temp_file"
        error "Transfer failed or no data received"
        echo ""
        read -p "Press Enter to continue..."
        return
    fi
    
    echo ""
    
    # Check if it's compressed
    if file "$temp_file" 2>/dev/null | grep -q "gzip compressed"; then
        log "Extracting folder..."
        
        # Use pigz for faster decompression if available
        if command_exists pigz; then
            pigz -d -c "$temp_file" | tar -xC "$output_dir" 2>/dev/null && \
            rm -f "$temp_file" && \
            success "Folder received: $output_dir"
        else
            tar -xzf "$temp_file" -C "$output_dir" 2>/dev/null && \
            rm -f "$temp_file" && \
            success "Folder received: $output_dir"
        fi
    else
        # Regular file
        local filename="received_$(date +%Y%m%d_%H%M%S)"
        
        # Auto-detect file extension
        if command_exists file; then
            local filetype=$(file -b --mime-type "$temp_file")
            case "$filetype" in
                application/pdf) filename="${filename}.pdf" ;;
                image/jpeg) filename="${filename}.jpg" ;;
                image/png) filename="${filename}.png" ;;
                application/zip) filename="${filename}.zip" ;;
                text/*) filename="${filename}.txt" ;;
                video/*) filename="${filename}.mp4" ;;
                audio/*) filename="${filename}.mp3" ;;
            esac
        fi
        
        mv "$temp_file" "$output_dir/$filename"
        local filesize=$(format_size $(get_size "$output_dir/$filename"))
        
        success "File received: $output_dir/$filename"
        info "Size: $filesize"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Handle command line arguments for quick access
handle_args() {
    if [ $# -gt 0 ]; then
        case "$1" in
            --receive|-r)
                if [ $# -lt 2 ]; then
                    error "Usage: $0 --receive IP:PORT [output_dir]"
                    exit 1
                fi
                
                print_header
                echo -e "${BOLD}📥 Quick Receive Mode${NC}"
                echo ""
                
                local save_dir="${3:-.}"
                receive_file_fast "$2" "$save_dir"
                exit 0
                ;;
            --help|-h)
                print_header
                echo "Usage:"
                echo "  $0                    # Interactive mode (recommended)"
                echo "  $0 --receive IP:PORT [dir]  # Quick receive mode"
                echo ""
                exit 0
                ;;
        esac
    fi
}

# Main execution
check_dependencies
handle_args "$@"
show_menu