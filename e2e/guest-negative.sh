Y=/home/eugene/iouring-lab/youki
cd $Y && ./contest run --runtime /home/eugene/iouring-lab/youki-main/target/release/youki --runtimetest $Y/runtimetest -t io_uring 2>&1 | grep -v "^$" | tail -12
