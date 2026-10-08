#!/bin/bash
# Inside the VM: let the youki binary create user namespaces, the way Ubuntu
# documents for rootless tools (profile with `userns,`), instead of turning
# kernel.apparmor_restrict_unprivileged_userns off globally.
echo "apparmor_restrict_unprivileged_userns=$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns)"
sudo tee /etc/apparmor.d/youki-test >/dev/null <<'EOF'
abi <abi/4.0>,
include <tunables/global>

profile youki-test /home/tester/youki flags=(unconfined) {
  userns,

  include if exists <local/youki-test>
}
EOF
sudo apparmor_parser -r /etc/apparmor.d/youki-test && echo "profile loaded"
