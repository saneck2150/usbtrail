FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG USER_UID=1000
ARG USER_GID=1000
ARG BPFTOOL_VERSION=v7.7.0

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="/opt/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        build-essential \
        bpftrace \
        ca-certificates \
        clang \
        clang-format \
        cmake \
        curl \
        gdb \
        git \
        libbpf-dev \
        libcap-dev \
        libelf-dev \
        libssl-dev \
        llvm \
        make \
        ninja-build \
        pkg-config \
        python3 \
        python3-pip \
        python3-venv \
        shellcheck \
        shfmt \
        strace \
        usbutils \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone \
        --depth 1 \
        --branch "${BPFTOOL_VERSION}" \
        --recurse-submodules \
        https://github.com/libbpf/bpftool.git \
        /tmp/bpftool \
    && make -C /tmp/bpftool/src -j"$(nproc)" \
    && make -C /tmp/bpftool/src install \
    && rm -rf /tmp/bpftool \
    && bpftool version

COPY tools/requirements-dev.txt /tmp/requirements-dev.txt

RUN python3 -m venv "${VIRTUAL_ENV}" \
    && "${VIRTUAL_ENV}/bin/python" -m pip install --upgrade pip \
    && "${VIRTUAL_ENV}/bin/python" -m pip install -r /tmp/requirements-dev.txt \
    && rm /tmp/requirements-dev.txt

RUN mkdir -p /home/usbtrail \
    && chown "${USER_UID}:${USER_GID}" /home/usbtrail

ENV HOME=/home/usbtrail

COPY docker/entrypoint.sh /usr/local/bin/usbtrail-entrypoint

RUN chmod +x /usr/local/bin/usbtrail-entrypoint

WORKDIR /workspace

USER ${USER_UID}:${USER_GID}

ENTRYPOINT ["/usr/local/bin/usbtrail-entrypoint"]
CMD ["bash"]