#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Dotfiles Installer for Termux
# Re-links configs and bootstraps TPM + persistence fixes
# ==============================================================================
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPM_DIR="$HOME/.tmux/plugins/tpm"

echo "==> Setting up symlinks from $DOTFILES_DIR to $HOME..."

# Helper: link source to destination with directory creation and backup
link_config() {
    local src="$1"
    local dst="$2"

    [ ! -e "$src" ] && return 0

    mkdir -p "$(dirname "$dst")"

    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        local backup="${dst}.backup.$(date +%s)"
        mv "$dst" "$backup"
        echo "    Backed up existing $dst to $backup"
    fi

    ln -sfn "$src" "$dst"
    echo "    Linked $dst -> $src"
}

# 1. Tmux
link_config "$DOTFILES_DIR/tmux/tmux.conf" "$HOME/.tmux.conf"
link_config "$DOTFILES_DIR/tmux/scripts" "$HOME/.tmux/scripts"

# 2. Neovim
link_config "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"

# 3. Bashrc
link_config "$DOTFILES_DIR/bash/.bashrc" "$HOME/.bashrc"

# 4. Termux Properties
link_config "$DOTFILES_DIR/termux/termux.properties" "$HOME/.termux/termux.properties"
command -v termux-reload-settings >/dev/null 2>&1 && termux-reload-settings || true

# 5. Antigravity Configuration & Skills
link_config "$DOTFILES_DIR/antigravity/AGENTS.md" "$HOME/.gemini/config/AGENTS.md"
link_config "$DOTFILES_DIR/antigravity/skills" "$HOME/.gemini/config/skills"
link_config "$DOTFILES_DIR/antigravity/hooks.json" "$HOME/.gemini/config/hooks.json"
link_config "$DOTFILES_DIR/antigravity/scripts" "$HOME/.gemini/config/scripts"

# 6. Global CLI Utilities
link_config "$DOTFILES_DIR/bin/prep" "${PREFIX:-/data/data/com.termux/files/usr}/bin/prep"

# ==============================================================================
# Tmux Plugins
# ==============================================================================
echo "==> Checking Tmux Plugin Manager (TPM)..."
if [ ! -d "$TPM_DIR" ]; then
    echo "    Cloning TPM..."
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi

if command -v termux-fix-shebang >/dev/null 2>&1; then
    echo "==> Fixing TPM script shebangs for Termux..."
    termux-fix-shebang "$TPM_DIR/bin/"* "$TPM_DIR/scripts/"* "$TPM_DIR/tpm" 2>/dev/null || true
fi

# Plugins are listed in tmux.conf
echo "==> Installing Tmux plugins..."
"$TPM_DIR/bin/install_plugins"

echo "==> Applying Termux-specific fixes to Tmux plugins..."
if command -v termux-fix-shebang >/dev/null 2>&1; then
    find "$HOME/.tmux/plugins" -type f -exec termux-fix-shebang {} + 2>/dev/null || true
fi

# Fix /tmp permission bug in tmux-continuum
CONTINUUM_SAVE="$HOME/.tmux/plugins/tmux-continuum/scripts/continuum_save.sh"
if [ -f "$CONTINUUM_SAVE" ]; then
    sed -i 's|/tmp/tmux-continuum-|${TMPDIR:-/data/data/com.termux/files/usr/tmp}/tmux-continuum-|g' "$CONTINUUM_SAVE"
    echo "    Patched tmux-continuum lock directory path."
fi

# ==============================================================================
# Neovim Plugins
# ==============================================================================
echo "==> Installing Neovim plugins via lazy.nvim..."
nvim --headless "+Lazy! restore" +qa

# ==============================================================================
# Agent Skills Dependencies
# ==============================================================================
if [ -f "$DOTFILES_DIR/antigravity/skills/requirements.txt" ] && command -v pip >/dev/null 2>&1; then
    echo "==> Installing Python dependencies for agent skills..."
    pip install -q -r "$DOTFILES_DIR/antigravity/skills/requirements.txt" || echo "    Warning: Some Python dependencies failed to install."
fi

echo "==> All dotfiles installed successfully!"
