#!/bin/bash

# Setup script for CNS Contract Prototyping pre-commit hooks
# This script installs the pre-commit hook that ensures code formatting

set -e

echo "🔧 Setting up pre-commit hooks for CNS Contract Prototyping..."

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    echo "❌ Not in a git repository"
    echo "Please run this script from the root of your git repository"
    exit 1
fi

# Check if forge is available
if ! command -v forge &> /dev/null; then
    echo "❌ Foundry (forge) is not installed or not in PATH"
    echo "Please install Foundry: https://book.getfoundry.sh/getting-started/installation"
    exit 1
fi

# Create the pre-commit hook
echo "📝 Creating pre-commit hook..."

cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash

# Pre-commit hook to ensure Solidity code is properly formatted
# This hook runs `forge fmt --check` before allowing commits

set -e

echo "🔍 Running pre-commit checks..."

# Check if forge is available
if ! command -v forge &> /dev/null; then
    echo "❌ Foundry (forge) is not installed or not in PATH"
    echo "Please install Foundry: https://book.getfoundry.sh/getting-started/installation"
    exit 1
fi

# Check if we're in a Foundry project
if [ ! -f "foundry.toml" ]; then
    echo "❌ Not in a Foundry project (foundry.toml not found)"
    echo "Skipping formatting check..."
    exit 0
fi

echo "🔍 Checking Solidity code formatting..."

# Run forge fmt --check
if ! forge fmt --check; then
    echo ""
    echo "❌ Code formatting check failed!"
    echo ""
    echo "Please run 'forge fmt' to fix formatting issues before committing."
    echo ""
    echo "You can also run 'forge fmt --check' to see what needs to be fixed."
    echo ""
    exit 1
fi

echo "✅ Code formatting check passed!"
echo "🚀 Ready to commit!"
exit 0
EOF

# Make the hook executable
chmod +x .git/hooks/pre-commit

echo "✅ Pre-commit hook installed successfully!"
echo ""
echo "The hook will now run 'forge fmt --check' before each commit."
echo "If formatting issues are found, the commit will be blocked."
echo ""
echo "To fix formatting issues, run: forge fmt"
echo "To check formatting without fixing, run: forge fmt --check"
echo ""
echo "🎉 Setup complete!"
