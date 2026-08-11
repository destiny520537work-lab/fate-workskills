#!/usr/bin/env bash
# Extract user messages from local Claude Code transcripts for one local date.
# Usage: extract-day.sh YYYY-MM-DD [transcript-root] [IANA-timezone]
set -euo pipefail

DATE="${1:?Usage: $0 YYYY-MM-DD [transcript-root] [IANA-timezone]}"
DIR="${2:-$HOME/.claude/projects}"
ZONE="${3:-${TZ:-UTC}}"

if [[ ! -d "$DIR" ]]; then
  printf 'Transcript directory not found: %s\n' "$DIR" >&2
  exit 1
fi

read -r START END < <(python3 - "$DATE" "$ZONE" <<'PY'
import sys
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

day = date.fromisoformat(sys.argv[1])
zone = ZoneInfo(sys.argv[2])
start = datetime.combine(day, time.min, zone).astimezone(timezone.utc)
end = datetime.combine(day + timedelta(days=1), time.min, zone).astimezone(timezone.utc)
print(start.isoformat().replace('+00:00', 'Z'), end.isoformat().replace('+00:00', 'Z'))
PY
)

while IFS= read -r -d '' f; do
  jq -r --arg start "$START" --arg end "$END" '
    select(.type=="user" and (.isMeta|not) and (.isSidechain|not))
    | select((.timestamp // "") >= $start and (.timestamp // "") < $end)
    | .message.content as $c
    | (if ($c|type)=="string" then $c
       elif ($c|type)=="array" then ([$c[] | select(.type=="text") | .text] | join("\n"))
       else empty end) as $t
    | select($t != null and $t != "")
    | select(($t|startswith("<task-notification"))|not)
    | "[" + .timestamp + "] " + ($t | .[0:600] | gsub("\n"; " ⏎ "))
  ' "$f" 2>/dev/null || true
done < <(find "$DIR" -type f -name '*.jsonl' -print0) \
  | sort \
  | perl -pe 's/<(system-reminder|ide_opened_file|ide_selection|ide_diagnostics)>.*?<\/\1>//g; s/<command-(name|message|args)>.*?<\/command-\1>//g' \
  | awk '{gsub(/^\[|\]/,"",$1)} NF>1'
