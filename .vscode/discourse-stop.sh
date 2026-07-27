#!/usr/bin/env bash

pkill -f 'node ./bin/dev' 2>/dev/null || true
pkill -f 'rolldown.mjs' 2>/dev/null || true
sleep 1

echo "Discourse dev server stopped (killed bin/dev + any orphaned rolldown.mjs)."
