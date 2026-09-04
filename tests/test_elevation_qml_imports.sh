#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
elevation_dir="$project_root/elevation"
shared_components=(
    "$project_root/qml/components/ActionButton.qml"
    "$project_root/qml/components/FaceScanIndicator.qml"
)
temporary_dir=$(mktemp -d -t face-id-qml-imports.XXXXXX)
trap 'rm -rf -- "$temporary_dir"' EXIT
[[ -f $elevation_dir/ConsentPrompt.qml ]]

while IFS= read -r source_file; do
    while read -r keyword module _; do
        [[ $keyword == import ]] || continue
        if [[ ! $module =~ ^QtQuick([.][A-Za-z0-9_]+)*$ ]]; then
            printf 'Disallowed elevation QML import in %s: %s\n' \
                "$source_file" "$module" >&2
            exit 1
        fi
    done < <(sed -n '/^[[:space:]]*import[[:space:]]/p' "$source_file")
done < <(find "$elevation_dir" -maxdepth 1 -type f -name '*.qml' -print; \
         printf '%s\n' "${shared_components[@]}")

if rg -n '^[[:space:]]*import[[:space:]]+(qs([.]|[[:space:]])|Quickshell([.]|[[:space:]]))' \
    "$elevation_dir" "${shared_components[@]}" --glob '*.qml'; then
    echo 'The out-of-process elevation UI must not import shell-only QML modules.' >&2
    exit 1
fi

# qmlimportscanner parses imports without requiring the host to provide or
# resolve a particular Qt installation's import directory.
if command -v qmlimportscanner >/dev/null 2>&1; then
    qmlimportscanner -rootPath "$elevation_dir" >"$temporary_dir/imports.json"
    if grep -E '"name"[[:space:]]*:[[:space:]]*"(qs([.][^"]*)?|Quickshell([.][^"]*)?)"' \
        "$temporary_dir/imports.json"; then
        echo 'qmlimportscanner found a shell-only elevation QML dependency.' >&2
        exit 1
    fi
fi

# Exercise the actual consent surface through every state. The avatar must
# retain its initial screen position as controls and messages change below it.
qml_test_runner=
if [[ -x /usr/lib/qt6/bin/qmltestrunner ]]; then
    qml_test_runner=/usr/lib/qt6/bin/qmltestrunner
elif command -v qmltestrunner >/dev/null 2>&1; then
    qml_test_runner=$(command -v qmltestrunner)
fi
if [[ -n $qml_test_runner ]]; then
    cp "$elevation_dir/ConsentPrompt.qml" "$temporary_dir/"
    cp "${shared_components[@]}" "$temporary_dir/"
    cp "$project_root/tests/tst_consent_layout.qml" "$temporary_dir/"
    GSETTINGS_BACKEND=memory QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
        "$qml_test_runner" -input "$temporary_dir" -o -,txt
fi
