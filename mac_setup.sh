#!/usr/bin/env bash

# ##############################################################################
#
# macOS Setup Script (vNext - 2025 Edition)
#
# ##############################################################################

# --- Script Configuration: Fail Fast ---
set -e -o pipefail

# --- Helper Functions for colored output ---
print_info() { printf "\n\e[1;34m%s\e[0m\n" "$1"; }
print_success() { printf "\e[1;32m✓ %s\e[0m\n" "$1"; }
print_warning() { printf "\e[1;33m∙ %s\e[0m\n" "$1"; }
print_error() { printf "\e[1;31m✗ %s\e[0m\n" "$1"; }

# --- Abort if not on macOS ---
if [[ "$(uname)" != "Darwin" ]]; then echo "This script is for macOS only."; exit 1; fi

# --- Check and Install Homebrew ---
if ! command -v brew &> /dev/null; then
    print_info "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ "$(uname -m)" == "arm64" ]]; then
        (echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        (echo; echo 'eval "$(/usr/local/bin/brew shellenv)"') >> ~/.zshrc
        eval "$(/usr/local/bin/brew shellenv)"
    fi
else
    print_info "Homebrew is already installed."
fi

# --- Stage 1: Conditional Update and Upgrade ---
print_info "Checking when Homebrew was last updated..."
TWENTY_FOUR_HOURS_IN_SECONDS=86400
FETCH_HEAD_PATH="$(brew --repository)/.git/FETCH_HEAD"
run_update=false

if [ ! -f "$FETCH_HEAD_PATH" ]; then
    print_warning "Homebrew FETCH_HEAD not found. Forcing an update."
    run_update=true
else
    LAST_UPDATE=$(stat -f %m "$FETCH_HEAD_PATH")
    CURRENT_TIME=$(date +%s)
    if (( CURRENT_TIME - LAST_UPDATE > TWENTY_FOUR_HOURS_IN_SECONDS )); then
        print_info "Homebrew was last updated more than 24 hours ago. Updating and upgrading..."
        run_update=true
    else
        print_warning "Homebrew was updated within the last 24 hours. Skipping update/upgrade step."
    fi
fi

if [ "$run_update" = true ]; then
    brew update && brew upgrade && brew upgrade --cask
    if command -v mas &>/dev/null; then mas upgrade; fi
    print_success "All existing software has been upgraded."
fi


# --- Stage 2: Install Homebrew Software ---
print_info "Installing all declared software from the Brewfile..."
brew bundle install --file=- <<EOF
# --- Casks (GUI Applications) ---
cask "alt-tab"
cask "android-platform-tools"
cask "anythingllm"
cask "applepi-baker"
cask "bitwarden"
cask "brave-browser"
cask "bruno"
cask "docker"
cask "ente"
cask "ente-auth"
cask "font-hack-nerd-font"
cask "ghostty"
cask "git-credential-manager"
cask "goland"
cask "google-chrome"
cask "handbrake"
cask "jordanbaird-ice"
cask "lulu"
cask "macfuse"
cask "notesnook"
cask "nordvpn"
cask "ollama"
cask "openmtp"
cask "paintbrush"
cask "pearcleaner"
cask "postico"
cask "proton-drive"
cask "proton-mail"
cask "rectangle"
cask "rustdesk"
cask "stremio"
cask "syncthing"
cask "the-unarchiver"
cask "transmission"
cask "utm"
cask "vlc"
cask "vscodium"
cask "whatsapp"

# --- Formulae (CLI Tools) ---
brew "bitwarden-cli"
brew "buf"
brew "eslint"
brew "ffmpeg"
brew "gh"
brew "git"
brew "git-filter-repo"
brew "goenv"
brew "golang-migrate"
brew "golangci-lint"
brew "mas"
brew "nvm"
brew "pnpm"
brew "powerlevel10k"
brew "prettier"
brew "pv"
brew "pyenv"
brew "postgresql"
brew "shellcheck"
brew "tmux"
brew "tree"
brew "unar"
brew "zsh-autosuggestions"
brew "zsh-history-substring-search"
brew "zsh-syntax-highlighting"
EOF
print_success "All Homebrew software is installed."

# --- Stage 3: Special Configurations (SourceGit) ---
print_info "Handling SourceGit installation/upgrade..."
SOURCEGIT_ACTION_TAKEN=false
if ! brew list --cask | grep -q "^sourcegit$"; then
    print_info "SourceGit not found. Installing..."
    if ! brew tap | grep -q "ybeapps/sourcegit"; then brew tap ybeapps/homebrew-sourcegit; fi
    brew install --cask --no-quarantine sourcegit
    SOURCEGIT_ACTION_TAKEN=true
elif brew outdated --cask | grep -q "^sourcegit$"; then
    print_info "SourceGit is outdated. Upgrading..."
    brew upgrade --cask --no-quarantine sourcegit
    SOURCEGIT_ACTION_TAKEN=true
else
    print_warning "SourceGit is already installed and up-to-date."
fi

if [ "$SOURCEGIT_ACTION_TAKEN" = true ]; then
    print_info "Performing post-install configuration for SourceGit..."
    sudo xattr -cr /Applications/SourceGit.app
    mkdir -p "$HOME/Library/Application Support/SourceGit"
    echo "$PATH" > "$HOME/Library/Application Support/SourceGit/PATH"
    print_success "SourceGit configured."
fi


# --- Stage 4: Shell and Language Setup ---
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    print_info "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    print_warning "Oh My Zsh is already installed."
fi

print_info "Creating .zshrc configuration file..."
cat << 'EOF' > "$HOME/.zshrc"
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(alias-finder aliases brew command-not-found dircycle git history npm sudo tmux)
source "$ZSH/oh-my-zsh.sh"
export EDITOR='codium'
export PATH="$PATH:$HOME/go/bin"
if command -v pyenv &>/dev/null; then eval "$(pyenv init -)"; fi
if command -v goenv &>/dev/null; then eval "$(goenv init -)"; fi
export NVM_DIR="$HOME/.nvm"
[ -s "$(brew --prefix)/opt/nvm/nvm.sh" ] && \. "$(brew --prefix)/opt/nvm/nvm.sh"
if [ -f "$(brew --prefix)/share/powerlevel10k/powerlevel10k.zsh-theme" ]; then
  source "$(brew --prefix)/share/powerlevel10k/powerlevel10k.zsh-theme"
fi
if [ -f "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
  source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
if [ -f "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]; then
  source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi
source "$(brew --prefix)/share/zsh-history-substring-search/zsh-history-substring-search.zsh"
if [ -d "$HOME/.docker/completions" ]; then
  fpath=($HOME/.docker/completions $fpath)
fi
autoload -Uz compinit && compinit
EOF
print_success ".zshrc file created successfully."

print_info "Checking and installing Node.js and Go versions..."
export NVM_DIR="$HOME/.nvm"
[ -s "$(brew --prefix)/opt/nvm/nvm.sh" ] && \. "$(brew --prefix)/opt/nvm/nvm.sh"
if command -v goenv &>/dev/null; then 
    export GOENV_ROOT="$HOME/.goenv"
    export PATH="$GOENV_ROOT/bin:$PATH"
    eval "$(goenv init -)"
fi

if ! command -v nvm &> /dev/null; then print_error "nvm command not found. Exiting."; exit 1; fi
if ! command -v goenv &> /dev/null; then print_error "goenv command not found. Exiting."; exit 1; fi

if ! nvm ls lts/* > /dev/null 2>&1; then print_info "Installing latest LTS Node.js..."; nvm install --lts; else print_warning "Node.js LTS already installed."; fi
if ! nvm ls node > /dev/null 2>&1; then print_info "Installing latest Current Node.js..."; nvm install node; else print_warning "Node.js Current already installed."; fi
nvm alias default lts/*
print_info "Enabling Corepack..."; corepack enable || true

STABLE_GO_VERSIONS=$(goenv install -l | grep -v -E 'alpha|beta|rc' || true)
if [ -z "$STABLE_GO_VERSIONS" ]; then
    print_error "Could not retrieve list of stable Go versions. Skipping Go installation."
else
    LTS_MAJOR_GO=$(echo "$STABLE_GO_VERSIONS" | sed 's/^\s*//' | cut -d'.' -f1,2 | uniq | tail -n 2 | head -n 1 | xargs)
    LATEST_GO=$(echo "$STABLE_GO_VERSIONS" | tail -1 | xargs)
    LTS_GO=$(echo "$STABLE_GO_VERSIONS" | grep -E "^\s*${LTS_MAJOR_GO}" | tail -n 1 | xargs)
    
    if [ -d "$(goenv root)/versions/${LTS_GO}" ]; then print_warning "Go 'LTS' version ($LTS_GO) is already installed. Skipping."; else print_info "Installing Go 'LTS' ($LTS_GO)..."; goenv install "$LTS_GO"; fi
    if [ -d "$(goenv root)/versions/${LATEST_GO}" ]; then print_warning "Go latest version ($LATEST_GO) is already installed. Skipping."; else print_info "Installing Go latest ($LATEST_GO)..."; goenv install "$LATEST_GO"; fi
    goenv global "$LATEST_GO"
fi
print_success "Shell and language runtimes are configured."


# --- Stage 5: Interactive Login Finale ---
print_info "--- INTERACTIVE SETUP & LOGIN ---"
BW_LOGIN_REQUIRED=false
GH_LOGIN_NEEDED=false
DOCKER_LOGIN_NEEDED=false
MAS_INSTALL_REQUESTED=false

# Check GitHub status
if ! gh auth status &>/dev/null; then
    print_warning "GitHub CLI is not logged in."
    GH_LOGIN_NEEDED=true
    BW_LOGIN_REQUIRED=true
else
    print_success "GitHub CLI is already logged in."
fi

# Check Docker status by looking for the auths block in the config file
if [ ! -f "$HOME/.docker/config.json" ] || ! grep -q "auths" "$HOME/.docker/config.json"; then
    print_warning "Docker is not logged in."
    DOCKER_LOGIN_NEEDED=true
    BW_LOGIN_REQUIRED=true
else
    print_success "Docker is already logged in."
fi

# Ask about App Store apps
read -p "Do you want to install Mac App Store apps? (y/N): " mas_choice
if [[ "$mas_choice" =~ ^[Yy]$ ]]; then
    MAS_INSTALL_REQUESTED=true
    BW_LOGIN_REQUIRED=true # Required to fetch Apple ID creds
fi

# Main conditional login block
if [ "$BW_LOGIN_REQUIRED" = true ]; then
    print_info "Action required. Unlocking Bitwarden..."
    bw logout > /dev/null 2>&1 || true # Ensure clean state
    read -p "Enter your Bitwarden email address: " bw_email
    read -s -p "Enter your Bitwarden master password: " bw_password
    echo ""
    read -p "Enter your Bitwarden 2FA/OTP code: " bw_otp
    export BW_SESSION=$(bw login "$bw_email" "$bw_password" --code "$bw_otp" --raw)

    if [ -z "$BW_SESSION" ]; then
        print_error "Bitwarden login failed or was cancelled. Skipping all automated logins."
    else
        print_success "Bitwarden unlocked for this session."
        
        # Perform queued actions
        if [ "$GH_LOGIN_NEEDED" = true ]; then
            GH_TOKEN=$(bw get password "GitHub PAT")
            if [ -n "$GH_TOKEN" ]; then echo "$GH_TOKEN" | gh auth login --with-token; print_success "GitHub login complete."; else print_error "Could not find 'GitHub PAT'. Skipping."; fi
        fi

        if [ "$DOCKER_LOGIN_NEEDED" = true ]; then
            DOCKER_USER=$(bw get username "Docker Hub")
            DOCKER_PASS=$(bw get password "Docker Hub")
            if [ -n "$DOCKER_USER" ] && [ -n "$DOCKER_PASS" ]; then echo "$DOCKER_PASS" | docker login --username "$DOCKER_USER" --password-stdin; print_success "Docker Hub login complete."; else print_error "Could not find 'Docker Hub'. Skipping."; fi
        fi

        if [ "$MAS_INSTALL_REQUESTED" = true ]; then
            print_info "Fetching Apple ID credentials from Bitwarden for your convenience..."
            APPLE_ID_USER=$(bw get username "Apple ID" || echo "Not Found")
            APPLE_ID_PASS=$(bw get password "Apple ID" || echo "Not Found")
            
            # Log out of Bitwarden immediately after fetching the last credential
            print_info "Locking Bitwarden vault..."
            unset BW_SESSION
            bw logout > /dev/null 2>&1 || true

            if [[ "$APPLE_ID_USER" != "Not Found" ]]; then
                print_warning "Your credentials are listed below. The script will now proceed."
                print_warning "If you are not logged into the App Store, a GUI prompt will appear."
                echo "  Apple ID: $APPLE_ID_USER"
                echo "  Password: $APPLE_ID_PASS"
                read -p "Press [Enter] to begin App Store installation..."
            else
                print_error "Could not find 'Apple ID' in Bitwarden. You will need to enter your credentials manually."
                read -p "Press [Enter] to begin App Store installation..."
            fi
            
            print_info "Installing App Store app: Outlook..."
            # mas install 1352778147 # Bitwarden
            # mas install 905953485  # NordVPN
            mas install 985367838  # Microsoft Outlook
            print_success "App Store apps installation process complete."
        fi
        
        # If we didn't do App Store, log out now
        if [ -n "$BW_SESSION" ]; then
            print_info "Locking Bitwarden vault..."
            unset BW_SESSION
            bw logout > /dev/null 2>&1 || true
        fi
    fi
else
    print_success "All CLI tools are already logged in and App Store installs were skipped. Nothing to do."
fi

# --- Stage 6: Final Cleanup ---
print_info "Cleaning up Homebrew cache..."
brew cleanup
print_success "Cleanup complete."

print_info "Setup finished! Reloading shell to apply changes..."
exec zsh -l