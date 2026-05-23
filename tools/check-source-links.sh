#!/usr/bin/env bash
set -euo pipefail

shopt -s globstar nullglob

files=(README.md SUMMARY.md docs/**/*.md)
status=0

echo "Checking markdown links..."
for file in "${files[@]}"; do
    while IFS= read -r target; do
        case "$target" in
            http:*|https:*|mailto:*|\#*) continue ;;
        esac

        path="${target%%#*}"
        [ -z "$path" ] && continue

        if [[ "$path" = /* ]]; then
            candidate=".$path"
        else
            candidate="$(dirname "$file")/$path"
        fi

        if [ ! -e "$candidate" ]; then
            echo "Missing link target in $file: $target"
            status=1
        fi
    done < <(perl -ne 'while (/\[[^\]]+\]\(([^)]+)\)/g) { print "$1\n"; }' "$file")
done

if [ -d FreeRTOS-Kernel ]; then
    echo "Checking FreeRTOS-Kernel source references..."
    while IFS= read -r ref; do
        ref="${ref#\`}"
        ref="${ref%\`}"
        path="${ref%%:*}"

        if [ ! -e "$path" ]; then
            echo "Missing source reference: $ref"
            status=1
        fi
    done < <(grep -rhoE '`FreeRTOS-Kernel/[^`[:space:]]+`' "${files[@]}" | sort -u)
else
    echo "Skipping FreeRTOS-Kernel source references; upstream source is not vendored."
fi

echo "Checking markdown titles..."
for file in docs/**/*.md README.md SUMMARY.md; do
    if ! grep -qE '^#+[[:space:]]+' "$file"; then
        echo "Missing visible title in $file"
        status=1
    fi
done

if [ "$status" -eq 0 ]; then
    echo "All documentation checks passed."
fi

exit "$status"
