# orca-strait — parallel TDD orchestrator plugin

# Set up local git hooks and install the plugin. Run once after cloning.
init:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "==> orca-strait: plugin init"

    # 1. Wire local hooks
    git config core.hooksPath .githooks
    chmod +x .githooks/pre-commit .githooks/post-commit .githooks/pre-push
    echo "    hooks: .githooks wired"

    # 2. Verify claude is available
    if ! command -v claude >/dev/null 2>&1; then
        echo "    ERROR: 'claude' not on PATH — install Claude Code first"
        echo "    https://claude.ai/code"
        exit 1
    fi

    # 3. Verify prerequisites
    MISSING=""
    command -v cargo >/dev/null 2>&1 || MISSING="$MISSING cargo"
    command -v gh    >/dev/null 2>&1 || MISSING="$MISSING gh"
    if [ -n "$MISSING" ]; then
        echo "    WARNING: missing tools:$MISSING"
        echo "    orca-strait requires these for TDD agent dispatch."
        printf "    Continue anyway? [y/N] "
        read -r ans
        [ "$ans" = "y" ] || [ "$ans" = "Y" ] || exit 1
    fi

    # 4. Register local marketplace if not already registered
    MARKETPLACE="$HOME/.claude/plugins/local-marketplace"
    if [ -d "$MARKETPLACE" ]; then
        claude plugin marketplace add "$MARKETPLACE" 2>/dev/null || true
        echo "    marketplace: local registered"
    else
        echo "    WARNING: local marketplace not found at $MARKETPLACE"
    fi

    # 5. Install / reinstall plugin
    claude plugin uninstall orca-strait --force 2>/dev/null || true
    claude plugin install orca-strait@bazaar
    echo "    plugin: orca-strait installed"

    echo ""
    echo "==> Done. Restart Claude Code to apply."

# Reinstall plugin without re-running full init
reinstall:
    #!/usr/bin/env bash
    claude plugin uninstall orca-strait --force 2>/dev/null || true
    claude plugin install orca-strait@bazaar
    echo "[orca-strait] reinstalled — restart Claude Code to apply"
