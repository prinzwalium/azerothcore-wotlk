# Stage 1: Der Builder (kompiliert den Code)
FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

# Bausteine und Compiler installieren
RUN apt-get update && apt-get install -y \
    git cmake make gcc g++ clang libssl-dev libbz2-dev libreadline-dev \
    libncurses-dev libboost-all-dev libmariadb-dev-compat libmariadb-dev

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

# Stage 2: Der Runner (das finale Image)
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# Nur die Laufzeitumgebung installieren
RUN apt-get update && apt-get install -y \
    libssl3 mariadb-client tzdata curl unzip git \
    libboost-all-dev \
    libmariadb3 libreadline8 libbz2-1.0 libncurses6 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /azerothcore

# Die fertigen Server-Dateien kopieren
COPY --from=builder /azerothcore/env/dist ./env/dist
COPY --from=builder /export/sql-custom ./sql-custom

# Das Automatisierungs-Skript kopieren und ausführbar machen
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Das Skript fängt jeden Startbefehl ab und bereitet die Configs vor
ENTRYPOINT ["/entrypoint.sh"]
