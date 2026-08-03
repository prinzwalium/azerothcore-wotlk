#!/bin/bash
set -e

echo "[AutoSetup] Bereite Konfigurationsdateien vor..."
CONF_DIR="/azerothcore/env/dist/etc"
DATA_DIR="/azerothcore/env/dist/data"

# Configs aus den Vorlagen erstellen
cp -n $CONF_DIR/worldserver.conf.dist $CONF_DIR/worldserver.conf 2>/dev/null || true
cp -n $CONF_DIR/authserver.conf.dist $CONF_DIR/authserver.conf 2>/dev/null || true
mkdir -p $CONF_DIR/modules
cp -n $CONF_DIR/modules/playerbots.conf.dist $CONF_DIR/modules/playerbots.conf 2>/dev/null || true

# Zugangsdaten eintragen
DB_PASS=${DB_PASSWORD:-"8BvjmZFexf9piYpqHKnIzIm5ysIXBbFwsDbao6qXJpQiSyzp8A13qoZ9sI1D5txm"}
sed -i "s/127.0.0.1;3306;acore;acore/ac-database;3306;root;${DB_PASS}/g" $CONF_DIR/worldserver.conf
sed -i "s/127.0.0.1;3306;acore;acore/ac-database;3306;root;${DB_PASS}/g" $CONF_DIR/authserver.conf
sed -i "s/127.0.0.1;3306;acore;acore/ac-database;3306;root;${DB_PASS}/g" $CONF_DIR/modules/playerbots.conf 2>/dev/null || true

# Den Pfad zu den Map-Daten in der Config anpassen
sed -i 's/^DataDir =.*/DataDir = "\/azerothcore\/env\/dist\/data"/g' $CONF_DIR/worldserver.conf

# --- NEU: Der automatische Map-Downloader ---
if [ ! -d "$DATA_DIR/dbc" ]; then
    echo "[AutoSetup] Map-Daten nicht gefunden! Lade Client-Daten herunter (Das dauert einige Minuten)..."
    curl -L -o $DATA_DIR/data.zip https://github.com/wowgaming/client-data/releases/download/v8/data.zip
    
    echo "[AutoSetup] Entpacke Map-Daten..."
    unzip -q $DATA_DIR/data.zip -d $DATA_DIR
    
    echo "[AutoSetup] Lösche Zip-Archiv..."
    rm $DATA_DIR/data.zip
    
    echo "[AutoSetup] Map-Daten erfolgreich installiert!"
else
    echo "[AutoSetup] Map-Daten bereits vorhanden, überspringe Download."
fi
# --------------------------------------------

echo "[AutoSetup] Configs bereit! Starte Server..."

# Server-Befehl ausführen
exec "$@"
