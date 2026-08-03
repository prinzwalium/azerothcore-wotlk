#!/bin/bash
set -e

echo "[AutoSetup] Bereite Konfigurationsdateien vor..."
CONF_DIR="/azerothcore/env/dist/etc"

# Configs aus den Vorlagen erstellen (überschreibt keine existierenden Configs)
cp -n $CONF_DIR/worldserver.conf.dist $CONF_DIR/worldserver.conf 2>/dev/null || true
cp -n $CONF_DIR/authserver.conf.dist $CONF_DIR/authserver.conf 2>/dev/null || true
mkdir -p $CONF_DIR/modules
cp -n $CONF_DIR/modules/playerbots.conf.dist $CONF_DIR/modules/playerbots.conf 2>/dev/null || true

# Datenbank-Passwort aus der Umgebungsvariable auslesen
DB_PASS=${DB_PASSWORD:-"8BvjmZFexf9piYpqHKnIzIm5ysIXBbFwsDbao6qXJpQiSyzp8A13qoZ9sI1D5txm"}

# Die Standardverbindung (127.0.0.1) in allen Configs durch den Docker-Datenbanknamen (ac-database) ersetzen
sed -i "s/127.0.0.1;3306;acore;acore/ac-database;3306;root;${DB_PASS}/g" $CONF_DIR/worldserver.conf
sed -i "s/127.0.0.1;3306;acore;acore/ac-database;3306;root;${DB_PASS}/g" $CONF_DIR/authserver.conf
sed -i "s/127.0.0.1;3306;acore;acore/ac-database;3306;root;${DB_PASS}/g" $CONF_DIR/modules/playerbots.conf 2>/dev/null || true

echo "[AutoSetup] Configs bereit! Starte Server..."

# Führe den eigentlichen Server-Befehl aus (worldserver oder authserver)
exec "$@"
