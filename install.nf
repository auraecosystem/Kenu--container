#!/usr/bin/env bash
# ai_cli_installer - Installer for AI CLI tools
# Version: 3.2.0

set -euo pipefail

###############################################################################
## Constants
###############################################################################
readonly SCRIPT_VERSION="3.2.0"
readonly SCRIPT_NAME="$(basename "$0")"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Package definitions (Bash 3.2 compatible - no associative arrays)
# Format: package_name:npm_package
PACKAGES="claude:@anthropic-ai/claude-code codex:@openai/codex gemini:@google/gemini-cli"

# Helper function to get npm package name
get_npm_package() {
    local key="$1"
    for pkg in $PACKAGES; do
        if [[ "${pkg%%:*}" == "$key" ]]; then
            echo "${pkg#*:}"
            return 0
        fi
    done
    return 1
}

# Helper function to list available packages
list_package_names() {
    local names=""
    for pkg in $PACKAGES; do
        names="$names ${pkg%%:*}"
    done
    echo "${names# }"  # Remove leading space
}

###############################################################################
## Output Functions
###############################################################################
info()    { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
warn()    { printf "${YELLOW}[WARN]${NC} %s\n" "$*" >&2; }
error()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
success() { printf "${GREEN}[✓]${NC} %s\n" "$*"; }

###############################################################################
## Help & Version
###############################################################################
show_version() {
    echo "${SCRIPT_NAME} version ${SCRIPT_VERSION}"
}

show_help() {
    cat <<EOF
${SCRIPT_NAME} - Install AI CLI tools

USAGE:
    ${SCRIPT_NAME} [OPTIONS]

OPTIONS:
    -p, --packages LIST    Comma-separated list of packages to install
                          Available: $(list_package_names)
                          Default: all available packages
    -g, --global          Install globally (requires sudo)
                          Default: user-local installation
    -d, --dry-run         Show what would be done without making changes
    -l, --list            List available packages
    -v, --version         Show version information
    -h, --help            Show this help message

EXAMPLES:
    ${SCRIPT_NAME}                    # Install all tools (user-local)
    ${SCRIPT_NAME} -p claude          # Install only Claude (user-local)
    ${SCRIPT_NAME} -p claude,gemini   # Install Claude and Gemini
    ${SCRIPT_NAME} --global           # Install globally (requires sudo)
    ${SCRIPT_NAME} --dry-run          # Preview changes

EOF
}

###############################################################################
## Utility Functions
###############################################################################
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_shell() {
    basename "$SHELL"
}

get_shell_rc() {
    local shell_name="$1"
    case "$shell_name" in
        bash) echo "${HOME}/.bashrc" ;;
        zsh)  echo "${HOME}/.zshrc" ;;
        fish) echo "${HOME}/.config/fish/config.fish" ;;
        *)    echo "" ;;
    esac
}

add_to_path() {
    local npm_bin="$1"
    local shell_name=$(detect_shell)
    local rc_file=$(get_shell_rc "$shell_name")
    
    if [[ -z "$rc_file" ]]; then
        warn "Unsupported shell: $shell_name. Please add $npm_bin to PATH manually."
        return 1
    fi
    
    local export_line
    case "$shell_name" in
        fish) 
            # Use fish_user_paths for proper persistence
            export_line="set -U fish_user_paths $npm_bin \$fish_user_paths" 
            ;;
        *)    
            export_line="export PATH=\"$npm_bin:\$PATH\"" 
            ;;
    esac
    
    # Check if PATH entry already exists
    if [[ -f "$rc_file" ]] && grep -qF "$npm_bin" "$rc_file" 2>/dev/null; then
        info "PATH already configured in $rc_file" >&2
    else
        echo "" >> "$rc_file"
        echo "# Added by ${SCRIPT_NAME} on $(date)" >> "$rc_file"
        echo "$export_line" >> "$rc_file"
        info "Added $npm_bin to PATH in $rc_file" >&2
    fi
    
    # Export for current session (with duplication guard)
    if [[ ":$PATH:" != *":$npm_bin:"* ]]; then
        export PATH="$npm_bin:$PATH"
    fi
}

check_node_version() {
    if ! command_exists node; then
        error "Node.js is not installed. Please install Node.js 18 or higher."
        return 1
    fi
    
    # Try node -p first, fallback to version string parsing
    local major_version=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null \
                          || node --version | sed 's/v//' | cut -d. -f1)
    
    if [[ "$major_version" -lt 18 ]]; then
        error "Node.js 18 or higher required. Found: v$(node --version | sed 's/v//')"
        return 1
    fi
    
    info "Node.js version: $(node --version)"
    return 0
}

###############################################################################
## Main Installation Logic
###############################################################################
setup_npm_prefix() {
    local force_global="$1"
    local install_global=false
    local npm_cmd="npm"
    local npm_prefix="${HOME}/.npm-global"
    
    if [[ "$force_global" == "true" ]]; then
        # User explicitly wants global installation
        if [[ $EUID -eq 0 ]]; then
            npm_cmd="npm"
            install_global=true
            npm_prefix=""
        elif command_exists sudo; then
            # Check if npm is available to sudo
            if sudo -n which npm >/dev/null 2>&1; then
                npm_cmd="sudo npm"
                install_global=true
                npm_prefix=""
            else
                error "Cannot install globally: npm not available to sudo (likely installed via version manager)" >&2
                error "Try without --global flag for user-local installation" >&2
                exit 1
            fi
        else
            error "Cannot install globally: no root access available" >&2
            error "Try without --global flag for user-local installation" >&2
            exit 1
        fi
        info "Installing globally (system-wide)" >&2
    else
        # Default: user-local installation
        mkdir -p "${npm_prefix}/lib" "${npm_prefix}/bin"
        npm config --global set prefix "${npm_prefix}" 2>/dev/null
        add_to_path "${npm_prefix}/bin"
        info "Installing to user directory: ${npm_prefix}" >&2
    fi
    
    # Return command and prefix (this MUST be the only stdout output)
    echo "${npm_cmd}|${npm_prefix}"
}

install_package() {
    local package_key="$1"
    local npm_package="$2"
    local npm_cmd="$3"
    local dry_run="$4"
    local npm_prefix="$5"
    
    if [[ "$dry_run" == "true" ]]; then
        info "[DRY RUN] Would install: $npm_package"
        return 0
    fi
    
    if command_exists "$package_key"; then
        info "Updating $package_key..."
        $npm_cmd update -g "$npm_package"
    else
        info "Installing $package_key..."
        $npm_cmd install -g "$npm_package"
    fi
    
    # For user-local installs, the command might not be in PATH yet
    # Check both current PATH and the npm prefix location
    if command_exists "$package_key"; then
        success "$package_key installed successfully"
    elif [[ -n "$npm_prefix" ]] && [[ -x "${npm_prefix}/bin/$package_key" ]]; then
        success "$package_key installed successfully (will be available after shell reload)"
    else
        error "Failed to install $package_key"
        return 1
    fi
}

###############################################################################
## Main Function
###############################################################################
main() {
    local packages_to_install=""
    local force_global=false
    local dry_run=false
    local list_packages=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--packages)
                [[ -z "${2:-}" ]] && { error "--packages requires an argument"; exit 1; }
                packages_to_install="$2"
                shift 2
                ;;
            -g|--global)
                force_global=true
                shift
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -l|--list)
                list_packages=true
                shift
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # List packages if requested
    if [[ "$list_packages" == "true" ]]; then
        echo "Available packages:"
        for pkg in $PACKAGES; do
            local name="${pkg%%:*}"
            local npm_pkg="${pkg#*:}"
            echo "  - $name ($npm_pkg)"
        done
        exit 0
    fi
    
    # Check prerequisites
    check_node_version || exit 1
    
    if ! command_exists npm; then
        error "npm is not installed"
        exit 1
    fi
    info "npm version: $(npm --version)"
    
    # Setup npm prefix
    IFS='|' read -r npm_cmd npm_prefix <<< "$(setup_npm_prefix "$force_global")"
    
    # Determine packages to install
    if [[ -z "$packages_to_install" ]]; then
        packages_to_install=$(list_package_names | tr ' ' ',')
    fi
    
    # Install packages
    IFS=',' read -ra requested_packages <<< "$packages_to_install"
    local failed=0
    
    for pkg in "${requested_packages[@]}"; do
        pkg=$(echo "$pkg" | tr -d ' ')  # Trim whitespace
        
        local npm_package=$(get_npm_package "$pkg")
        if [[ -z "$npm_package" ]]; then
            warn "Unknown package: $pkg"
            continue
        fi
        
        if ! install_package "$pkg" "$npm_package" "$npm_cmd" "$dry_run" "$npm_prefix"; then
            ((failed++))
        fi
    done
    
    # Summary
    echo
    if [[ $failed -eq 0 ]]; then
        success "All installations completed successfully!"
        
        # Check if PATH needs to be reloaded
        if [[ -n "$npm_prefix" ]]; then
            local shell_name=$(detect_shell)
            local rc_file=$(get_shell_rc "$shell_name")
            if [[ -n "$rc_file" ]]; then
                warn "Restart your shell or run: source $rc_file"
            fi
        fi
    else
        error "$failed package(s) failed to install."
        exit 1
    fi
}

# Run main function
main "$@"
