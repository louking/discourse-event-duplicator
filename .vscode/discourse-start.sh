#!/usr/bin/env bash
set -e

export PATH="$HOME/.nvm/versions/node/v24.18.0/bin:$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

cd ~/discourse

pkill -f 'node ./bin/dev' 2>/dev/null || true
pkill -f 'rolldown.mjs' 2>/dev/null || true
sleep 1

# setsid puts bin/dev in its own session, so the task terminal's SIGHUP on exit doesn't reach
# Pitchfork/rolldown (nohup alone only covers the top-level node process, not its children).
DISCOURSE_DISABLE_BROWSER_SANDBOX=1 setsid nohup node ./bin/dev > /tmp/discourse-dev.log 2>&1 < /dev/null &
disown

sleep 2
echo "Discourse dev server starting in background — tail -f /tmp/discourse-dev.log"
echo "or curl http://localhost:3000/ once it's up (can take ~30-60s)."
