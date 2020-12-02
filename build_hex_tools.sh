#!/bin/bash -x

set -euo pipefail

build_llvm_clang() {
	cd ${BASE}
	mkdir -p obj_llvm
	cd obj_llvm

	CC=clang CXX=clang++ cmake -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX:PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/ \
		-DLLVM_CCACHE_BUILD:BOOL=ON \
		-DLLVM_ENABLE_LLD:BOOL=ON \
		-DLLVM_ENABLE_LIBCXX:BOOL=ON \
		-DLLVM_ENABLE_ASSERTIONS:BOOL=ON \
		-DLLVM_ENABLE_PIC:BOOL=OFF \
		-DLLVM_TARGETS_TO_BUILD:STRING="X86;Hexagon" \
		-DLLVM_ENABLE_PROJECTS:STRING="clang;lld" \
		../llvm-project/llvm
 	ninja all install
	cd ${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin
	ln -sf clang hexagon-unknown-linux-musl-clang
	ln -sf clang++ hexagon-unknown-linux-musl-clang++
	ln -sf llvm-ar hexagon-unknown-linux-musl-ar
	ln -sf llvm-objdump hexagon-unknown-linux-musl-objdump
	ln -sf llvm-objcopy hexagon-unknown-linux-musl-objcopy
	ln -sf llvm-readelf hexagon-unknown-linux-musl-readelf
	ln -sf llvm-ranlib hexagon-unknown-linux-musl-ranlib

	# workaround for now:
	cat <<EOF > hexagon-unknown-linux-musl.cfg
-G0 --sysroot=${HEX_SYSROOT}
EOF
}

build_clang_rt() {
	cd ${BASE}
	mkdir -p obj_clang_rt
	cd obj_clang_rt
	cmake -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DLLVM_CONFIG_PATH:PATH=../obj_llvm/bin/llvm-config \
		-DCMAKE_ASM_FLAGS:STRING="-G0 -mlong-calls -fno-pic --target=hexagon-unknown-linux-musl " \
		-DCMAKE_SYSTEM_NAME:STRING=Linux \
		-DCMAKE_C_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang" \
		-DCMAKE_ASM_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang" \
		-DCMAKE_INSTALL_PREFIX:PATH=${HEX_TOOLS_TARGET_BASE} \
		-DCMAKE_CROSSCOMPILING:BOOL=ON \
		-DCMAKE_C_COMPILER_FORCED:BOOL=ON \
		-DCMAKE_CXX_COMPILER_FORCED:BOOL=ON \
		-DCOMPILER_RT_BUILD_BUILTINS:BOOL=ON \
		-DCOMPILER_RT_BUILTINS_ENABLE_PIC:BOOL=OFF \
		-DCMAKE_SIZEOF_VOID_P=4 \
		-DCOMPILER_RT_OS_DIR= \
		-DCAN_TARGET_hexagon=1 \
		-DCAN_TARGET_x86_64=0 \
		-DCOMPILER_RT_SUPPORTED_ARCH=hexagon \
		-DLLVM_ENABLE_PROJECTS:STRING="compiler-rt" \
		../llvm-project/compiler-rt
	ninja install-compiler-rt
}


build_canadian_clang() {
	cd ${BASE}
	mkdir -p obj_canadian
	cd obj_canadian

	cmake -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX:PATH=${ROOTFS} \
		-DLLVM_CCACHE_BUILD:BOOL=ON \
		-DLLVM_ENABLE_LIBCXX:BOOL=ON \
		-DLLVM_ENABLE_ASSERTIONS:BOOL=ON \
		-DCMAKE_CROSSCOMPILING:BOOL=ON \
		-DCMAKE_SYSTEM_NAME:STRING=Linux \
		-DCMAKE_C_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang" \
		-DCMAKE_ASM_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang" \
		-DCMAKE_CXX_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang++" \
		-DCMAKE_C_FLAGS:STRING="-G0 -mlong-calls --target=hexagon-unknown-linux-musl " \
		-DCMAKE_CXX_FLAGS:STRING="-G0 -mlong-calls --target=hexagon-unknown-linux-musl " \
		-DCMAKE_ASM_FLAGS:STRING="-G0 -mlong-calls --target=hexagon-unknown-linux-musl " \
		-DLLVM_TABLEGEN=${BASE}/obj_llvm/bin/llvm-tblgen \
		-DCLANG_TABLEGEN=${BASE}/obj_llvm/bin/clang-tblgen \
		-DLLVM_DEFAULT_TARGET_TRIPLE=hexagon-unknown-linux-musl \
		-DLLVM_TARGET_ARCH="Hexagon" \
		-DLLVM_BUILD_RUNTIME:BOOL=OFF \
		-DBUILD_SHARED_LIBS:BOOL=OFF \
		-DLLVM_INCLUDE_TESTS:BOOL=OFF \
    		-DLLVM_INCLUDE_EXAMPLE:BOOL=OFF \
    		-DLLVM_INCLUDE_UTILS:BOOL=OFF \
                -DLLVM_ENABLE_BACKTRACE:BOOL=OFF \
                -DLLVM_ENABLE_PIC:BOOL=OFF \
		-DLLVM_TARGETS_TO_BUILD:STRING="Hexagon" \
		-DLLVM_ENABLE_PROJECTS:STRING="clang;lld" \
		../llvm-project/llvm
        ninja all install
}


config_kernel() {
	cd ${BASE}
	mkdir -p obj_linux
	cd linux
	make O=../obj_linux ARCH=hexagon \
		KBUILD_CFLAGS_KERNEL="-mlong-calls" \
	       	CC=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/hexagon-unknown-linux-musl-clang \
	       	LD=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/ld.lld \
		KBUILD_VERBOSE=1 comet_defconfig
}
build_kernel() {
	${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/hexagon-unknown-linux-musl-clang --version
	cd ${BASE}
	cd obj_linux
	make -j $(nproc) \
		KBUILD_CFLAGS_KERNEL="-mlong-calls" \
      		ARCH=hexagon \
		KBUILD_VERBOSE=1 comet_defconfig \
		V=1 \
	       	CC=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/hexagon-unknown-linux-musl-clang \
	       	AS=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/hexagon-unknown-linux-musl-clang \
	       	LD=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/ld.lld \
	       	OBJCOPY=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/llvm-objcopy \
	       	OBJDUMP=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/llvm-objdump \
	       	LIBGCC=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/target/hexagon-unknown-linux-musl/lib/libclang_rt.builtins-hexagon.a \
		vmlinux
}
build_kernel_headers() {
	cd ${BASE}
	cd linux
	make mrproper
	cd ${BASE}
	cd obj_linux
	make \
	        ARCH=hexagon \
	       	CC=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/clang \
		INSTALL_HDR_PATH=${HEX_TOOLS_TARGET_BASE} \
		V=1 \
		headers_install
}

build_musl_headers() {
	cd ${BASE}
	cd musl
	make clean

	CC=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/hexagon-unknown-linux-musl-clang \
		CROSS_COMPILE=hexagon-unknown-linux-musl \
	       	LIBCC=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/target/hexagon-unknown-linux-musl/lib/libclang_rt.builtins-hexagon.a \
		CROSS_CFLAGS="-G0 -O0 -mv65 -fno-builtin  --target=hexagon-unknown-linux-musl" \
		./configure --target=hexagon --prefix=${HEX_TOOLS_TARGET_BASE}
	PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/:$PATH make CROSS_COMPILE= install-headers

	cd ${HEX_SYSROOT}/..
	ln -sf hexagon-unknown-linux-musl hexagon
}

build_musl() {
	cd ${BASE}
	cd musl
	make clean

	CROSS_COMPILE=hexagon-unknown-linux-musl- \
		AR=llvm-ar \
		RANLIB=llvm-ranlib \
		STRIP=llvm-strip \
	       	CC=clang \
	       	LIBCC=${HEX_TOOLS_TARGET_BASE}/lib/libclang_rt.builtins-hexagon.a \
		CFLAGS="${MUSL_CFLAGS}" \
		./configure --target=hexagon --prefix=${HEX_TOOLS_TARGET_BASE}
	PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/:$PATH make -j CROSS_COMPILE= install
	cd ${HEX_TOOLS_TARGET_BASE}/lib
	ln -sf libc.so ld-musl-hexagon.so
	ln -sf ld-musl-hexagon.so ld-musl-hexagon.so.1
	mkdir -p ${HEX_TOOLS_TARGET_BASE}/../lib
	cd ${HEX_TOOLS_TARGET_BASE}/../lib
	ln -sf ../usr/lib/ld-musl-hexagon.so.1
}

test_libc() {
	cd ${BASE}
	mkdir -p obj_libc-test/
	cd obj_libc-test

	rm -f ../libc-test/config.mak
	cat ../libc-test/config.mak.def - <<EOF >> ../libc-test/config.mak
CFLAGS+=${MUSL_CFLAGS}
EOF

	set +e
	PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/:$PATH \
		CC=${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang \
		QEMU_LD_PREFIX=${HEX_TOOLS_TARGET_BASE} \
		make V=1 \
		--directory=../libc-test \
		B=${PWD} \
		CROSS_COMPILE=hexagon-unknown-linux-musl- \
		AR=llvm-ar \
		RANLIB=llvm-ranlib \
		RUN_WRAP=${TOOLCHAIN_BIN}/qemu_wrapper.sh
	libc_result=${?}
	set -e
	cp ./REPORT ${RESULTS_DIR}/libc_test_REPORT
	head ./REPORT $(find ${PWD} -name '*.err' | sort) > ${RESULTS_DIR}/libc_test_failures_err.log
}

build_libs() {
	cd ${BASE}
	mkdir -p obj_libs
	cd obj_libs
	cmake -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DLLVM_CONFIG_PATH:PATH=../obj_llvm/bin/llvm-config \
		-DCMAKE_SYSTEM_NAME:STRING=Linux \
		-DCMAKE_EXE_LINKER_FLAGS:STRING="-lclang_rt.builtins-hexagon -nostdlib" \
		-DCMAKE_SHARED_LINKER_FLAGS:STRING="-lclang_rt.builtins-hexagon -nostdlib" \
		-DCMAKE_C_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang" \
		-DCMAKE_CXX_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang++" \
		-DCMAKE_ASM_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang" \
		-DLLVM_INCLUDE_BENCHMARKS:BOOL=OFF \
		-DLLVM_BUILD_BENCHMARKS:BOOL=OFF \
		-DLLVM_INCLUDE_RUNTIMES:BOOL=OFF \
		-DLLVM_ENABLE_PROJECTS:STRING="libcxx;libcxxabi;libunwind" \
		-DLLVM_ENABLE_LIBCXX:BOOL=ON \
		-DLLVM_BUILD_RUNTIME:BOOL=ON \
		-DCMAKE_INSTALL_PREFIX:PATH=${HEX_TOOLS_TARGET_BASE} \
		-DCMAKE_CROSSCOMPILING:BOOL=ON \
		-DHAVE_CXX_ATOMICS_WITHOUT_LIB:BOOL=ON \
		-DHAVE_CXX_ATOMICS64_WITHOUT_LIB:BOOL=ON \
		-DLIBCXX_HAS_MUSL_LIBC:BOOL=ON \
		-DLIBCXX_INCLUDE_TESTS:BOOL=OFF \
		-DLIBCXX_CXX_ABI=libcxxabi \
		-DLIBCXXABI_USE_LLVM_UNWINDER=ON \
		-DLIBCXXABI_HAS_CXA_THREAD_ATEXIT_IMPL=OFF \
		-DLIBCXXABI_ENABLE_SHARED:BOOL=ON \
		-DCMAKE_CXX_COMPILER_FORCED:BOOL=ON \
		../llvm-project/llvm
	ninja -v install-unwind
	ninja -v install-cxxabi
	ninja -v install-cxx
}

build_qemu() {
	cd ${BASE}
	mkdir -p obj_qemu
	cd obj_qemu
	../qemu/configure --disable-fdt --disable-capstone --disable-guest-agent \
	                  --disable-containers \
		--target-list=hexagon-linux-user --prefix=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu \

#	--cc=clang \
#	--cross-prefix=hexagon-unknown-linux-musl-
#	--cross-cc-hexagon="hexagon-unknown-linux-musl-clang" \
#		--cross-cc-cflags-hexagon="-mv67 --sysroot=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/target/hexagon-unknown-linux-musl"

	make -j
	make -j install

	cat <<EOF > ./qemu_wrapper.sh
#!/bin/bash

set -euo pipefail

export QEMU_LD_PREFIX=${HEX_TOOLS_TARGET_BASE}

exec ${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/qemu-hexagon \$*
EOF
	cp ./qemu_wrapper.sh ${TOOLCHAIN_BIN}/
	chmod +x ./qemu_wrapper.sh ${TOOLCHAIN_BIN}/qemu_wrapper.sh
}

test_qemu() {
	cd ${BASE}
	cd obj_qemu

	make check V=1 --keep-going 2>&1 | tee ${RESULTS_DIR}/qemu_test_check.log
	PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin:$PATH \
		QEMU_LD_PREFIX=${HEX_TOOLS_TARGET_BASE} \
		CROSS_CFLAGS="-G0 -O0 -mv65 -fno-builtin" \
		make check-tcg TIMEOUT=180 CROSS_CC_GUEST=hexagon-unknown-linux-musl-clang V=1 --keep-going 2>&1 | tee ${RESULTS_DIR}/qemu_test_check-tcg.log
	qemu_result=${?}
}

test_llvm() {
	cd ${BASE}
	mkdir -p obj_test-suite
	cd obj_test-suite

	cmake -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-C../llvm-test-suite/cmake/caches/O3.cmake \
		-DTEST_SUITE_CXX_ABI:STRING=libc++abi \
		-DTEST_SUITE_RUN_UNDER:STRING="${TOOLCHAIN_BIN}/qemu_wrapper.sh" \
		-DTEST_SUITE_RUN_BENCHMARKS:BOOL=ON \
		-DTEST_SUITE_LIT_FLAGS:STRING="--max-tests=10" \
		-DTEST_SUITE_LIT:FILEPATH="${BASE}/obj_llvm/bin/llvm-lit" \
		-DBENCHMARK_USE_LIBCXX:BOOL=ON \
		-DCMAKE_SYSTEM_NAME:STRING=Linux \
		-DCMAKE_C_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang" \
		-DCMAKE_CXX_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang++" \
		-DSMALL_PROBLEM_SIZE:BOOL=ON \
		../llvm-test-suite
	ninja
#	ninja check \ || /bin/true
	${BASE}/obj_llvm/bin/llvm-lit -v --max-tests=40 . \
	       	2>&1 | tee ${RESULTS_DIR}/llvm-test-suite.log || /bin/true
}

build_cpython() {
	cd ${BASE}
	mkdir -p obj_host_cpython
	cd obj_host_cpython
	../cpython/configure \
	      --disable-ipv6 \
              --with-ensurepip=no \
              --prefix=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/
	make -j
	make install

	cd ${BASE}

	mkdir -p obj_cpython
	cd obj_cpython
	cat <<EOF > ./config.site
ac_cv_file__dev_ptmx=no
ac_cv_file__dev_ptc=no
EOF
	PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/:$PATH \
		CONFIG_SITE=${PWD}/config.site \
       		READELF=llvm-readelf \
       		CC=hexagon-unknown-linux-musl-clang \
		CFLAGS="-mlong-calls -mv65 -static" \
		LDFLAGS="-static"  CPPFLAGS="-static" \
		../cpython/configure \
	       		--host=hexagon-unknown-linux-musl \
	       		--build=x86_64-linux-gnu \
	       		--disable-ipv6 \
                        --disable-shared \
                        --with-ensurepip=no \
                        --prefix=${ROOTFS}
	PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/:$PATH make -j
	PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/:$PATH make test || /bin/true
	PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/:$PATH make install
}

build_busybox() {
	cd ${BASE}
	mkdir -p obj_busybox
	cd obj_busybox

	PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/:$PATH \
		make -f ../busybox/Makefile defconfig \
		KBUILD_SRC=../busybox/ \
		AR=llvm-ar \
		RANLIB=llvm-ranlib \
		STRIP=llvm-strip \
	       	ARCH=hexagon \
		CFLAGS="-mlong-calls" \
       		CC=hexagon-unknown-linux-musl-clang \
		CROSS_COMPILE=hexagon-unknown-linux-musl-

	PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/:$PATH \
		make -j install \
		AR=llvm-ar \
		RANLIB=llvm-ranlib \
		STRIP=llvm-strip \
	       	ARCH=hexagon \
		KBUILD_VERBOSE=1 \
		CFLAGS="-G0 -mlong-calls" \
		CONFIG_PREFIX=${ROOTFS} \
       		CC=hexagon-unknown-linux-musl-clang \
		CROSS_COMPILE=hexagon-unknown-linux-musl-

}

purge_builds() {
	rm -rf ${BASE}/obj_*/
}

TOOLCHAIN_INSTALL_REL=${TOOLCHAIN_INSTALL}
TOOLCHAIN_INSTALL=$(readlink -f ${TOOLCHAIN_INSTALL})
TOOLCHAIN_BIN=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin
HEX_SYSROOT=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/target/hexagon-unknown-linux-musl
HEX_TOOLS_TARGET_BASE=${HEX_SYSROOT}/usr
ROOT_INSTALL_REL=${ROOT_INSTALL}
ROOTFS=$(readlink -f ${ROOT_INSTALL})
RESULTS_DIR=$(readlink -f ${RESULTS})

BASE=$(readlink -f ${PWD})

mkdir -p ${RESULTS_DIR}

MUSL_CFLAGS="-G0 -O0 -mv65 -fno-builtin  --target=hexagon-unknown-linux-musl"

# Workaround, 'C()' macro results in switch over bool:
MUSL_CFLAGS="${MUSL_CFLAGS} -Wno-switch-bool"
# Workaround, this looks like a bug/incomplete feature in the
# hexagon compiler backend:
MUSL_CFLAGS="${MUSL_CFLAGS} -Wno-unsupported-floating-point-opt"

build_llvm_clang
config_kernel
build_kernel_headers
build_musl_headers
build_clang_rt
build_musl

build_qemu

qemu_result=99
test_qemu


build_libs

cp -ra ${HEX_SYSROOT}/usr ${ROOTFS}/

# needs google benchmark changes to count hexagon cycles in order to build:
#test_llvm

# Recipe still needs tweaks:
#	ld.lld: error: crt1.c:(function _start_c: .text._start_c+0x5C): relocation R_HEX_B22_PCREL out of range: 2688980 is not in [-2097152, 2097151]; references __libc_start_main
#	>>> defined in ... hexagon-unknown-linux-musl/usr/lib/libc.so
#build_canadian_clang

# In order to have enough space on hosted environments to make the tarballs we may need to cleanup at this stage
if [[ ${PURGE_BUILDS-0} -eq 1 ]]; then
	purge_builds
fi

cd ${BASE}
if [[ ${MAKE_TARBALLS-0} -eq 1 ]]; then
    XZ_OPT="-8 --threads=0" tar cJf ${BASE}/hexagon_tools_install_$(date +"%Y_%b_%d").tar.xz -C $(dirname ${TOOLCHAIN_INSTALL_REL}) $(basename ${TOOLCHAIN_INSTALL_REL})
fi

libc_result=99
test_libc 2>&1 | tee ${RESULTS_DIR}/libc_test_detail.log

# Needs patch to avoid reloc error:
#build_kernel

build_cpython
build_busybox

cd ${BASE}

if [[ ${MAKE_TARBALLS-0} -eq 1 ]]; then
    XZ_OPT="-8 --threads=0" tar cJf ${BASE}/hexagon_rootfs_$(date +"%Y_%b_%d").tar.xz  -C $(dirname ${ROOT_INSTALL_REL}) $(basename ${ROOT_INSTALL_REL})

    XZ_OPT="-8 --threads=0" tar cJf ${BASE}/hexagon_tests_$(date +"%Y_%b_%d").tar.xz  -C $(dirname ${RESULTS_DIR}) $(basename ${RESULTS_DIR})
fi

echo done
echo libc: ${libc_result}
echo qemu: ${qemu_result}
exit ${qemu_result}
#exit $(( ${libc_result} + ${qemu_result} ))
