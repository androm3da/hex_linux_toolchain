#!/bin/bash

set -euo pipefail

git clone -q https://github.com/llvm/llvm-project &
git clone -q https://github.com/llvm/llvm-test-suite &
git clone --depth=1 -q git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git linux &
git clone --depth=1 -q https://github.com/python/cpython &
git clone --depth=1 -q git://repo.or.cz/libc-test &
git clone -q https://git.busybox.net/busybox/ &


git clone -q --branch=hexagon https://github.com/quic/musl &
git clone -q https://github.com/quic/qemu &

wait
wait
wait
wait
wait
wait
wait
wait

dump_checkout_info() {
	for d in ./*
	do
		if [[ -d ${d} ]]; then
			cd ${d}
			echo ${d}:
			git show --summary --no-notes
			echo -e '\n\n\n'
			cd -
		fi
	done
}

mkdir -p ${RESULTS}
dump_checkout_info 2>&1 | tee ${RESULTS}/git_checkouts.txt
