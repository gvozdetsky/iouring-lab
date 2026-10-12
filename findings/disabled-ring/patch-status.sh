#!/bin/bash
# Fetch the kernel patch thread from lore with b4 and list who replied.
MSGID=20261009-iouring-task-restrict-fix-v1-1-a49daf55a12c@gmail.com
export PATH="$HOME/kwork/b4venv/bin:$PATH"
command -v b4 >/dev/null || { echo "b4 not installed"; exit 1; }
b4 --version
out=$(mktemp -d)
b4 -q mbox -o "$out" "$MSGID" 2>&1 | tail -3
mbox=$(ls "$out"/*.mbx 2>/dev/null | head -1)
[ -n "$mbox" ] || { echo "no mbox fetched"; exit 1; }
echo "--- messages in thread"
python3 - "$mbox" <<'EOF'
import mailbox, sys, email.utils
for m in mailbox.mbox(sys.argv[1]):
    name, addr = email.utils.parseaddr(m["From"] or "")
    print(f'{m["Date"]} | {name or addr} | {m["Subject"]}')
EOF
echo "--- replies (bodies, quoted lines dropped)"
python3 - "$mbox" <<'EOF'
import mailbox, sys
msgs = list(mailbox.mbox(sys.argv[1]))
for m in msgs[1:]:
    body = m.get_payload(decode=True) if not m.is_multipart() else m.get_payload(0).get_payload(decode=True)
    text = (body or b"").decode("utf8", "replace")
    lines = [l for l in text.splitlines() if not l.startswith(">")]
    print(f'=== {m["From"]} — {m["Date"]}')
    print("\n".join(lines[:40]).strip())
EOF
