#!/bin/bash
# Zero - Run Flask apps locally for development
# Runs the wifi-portal or web app on your local machine

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
    echo "Usage: $0 <app> [port]"
    echo ""
    echo "Apps:"
    echo "  portal  - Run wifi-portal app (default port 8080)"
    echo "  web     - Run main web app (default port 8081)"
    echo ""
    echo "Examples:"
    echo "  $0 portal       # Run portal on http://localhost:8080"
    echo "  $0 web 9000     # Run web on http://localhost:9000"
}

run_app() {
    local app_dir="$1"
    local port="${2:-8080}"
    local app_name="$(basename $app_dir)"
    
    if [ ! -f "$app_dir/app.py" ]; then
        echo "Error: $app_dir/app.py not found"
        exit 1
    fi
    
    echo "========================================"
    echo "Starting $app_name on http://localhost:$port"
    echo "Press Ctrl+C to stop"
    echo "========================================"
    echo ""
    
    cd "$app_dir"
    FLASK_APP=app.py FLASK_ENV=development python3 -m flask run --host=0.0.0.0 --port=$port
}

case "${1:-}" in
    portal)
        run_app "$REPO_DIR/apps/wifi-portal" "${2:-8080}"
        ;;
    web)
        run_app "$REPO_DIR/apps/web" "${2:-8081}"
        ;;
    *)
        usage
        ;;
esac
