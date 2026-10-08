cd /home/eugene/iouring-lab/liburing/test
echo "kernel $(uname -r)"
for t in task-restrict-exec.t task-restrict.t; do
  setpriv --reuid=1000 --regid=1000 --clear-groups ./$t; echo "$t exit=$? (0 pass, 1 fail, 77 skip)"
done
