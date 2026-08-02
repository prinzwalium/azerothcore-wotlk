# Stage 1: Der Builder (kompiliert den Code)
FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

# Bausteine und Compiler installieren
RUN apt-get update && apt-get install -y \
    git cmake make gcc g++ clang libssl-dev libbz2-dev libreadline-dev \
    libncurses-dev libboost-all-dev default-libmysqlclient-dev

# Quellcode wird von GitHub Actions in diesen Ordner kopiert
WORKDIR /build
COPY . .

RUN git clone https://github.com/mod-playerbots/mod-playerbots.git modules/mod-playerbots

# Modul-SQLs für später sichern
RUN mkdir -p /export/sql-custom && \
    cp -r modules/mod-playerbots/data/sql/ /export/sql-custom/
    
# Kompilieren (wir nutzen Clang, da es schneller ist)
RUN mkdir build && cd build && \
    cmake ../ -DCMAKE_INSTALL_PREFIX=/azerothcore/env/dist \
    -DTOOLS_BUILD=all -DSCRIPTS=static \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ && \
    make -j$(nproc) && make install

# Stage 2: Der Runner (das finale, kleine Image für deinen VPS)
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# Nur die Laufzeitumgebung installieren (kein Compiler mehr nötig)
RUN apt-get update && apt-get install -y \
    libssl3 default-mysql-client tzdata curl unzip \
    libboost-system1.74.0 libboost-filesystem1.74.0 libboost-iostreams1.74.0 \
    libboost-program-options1.74.0 libboost-regex1.74.0 libboost-thread1.74.0 \
    libmysqlclient21 libreadline8 libbz2-1.0 libncurses6 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /azerothcore

# Die fertigen Server-Dateien aus Stage 1 kopieren
COPY --from=builder /azerothcore/env/dist ./env/dist
# Die SQL Dateien des Moduls für spätere DB-Updates kopieren
COPY --from=builder /export/sql-custom ./sql-custom

EXPOSE 8085 3724
