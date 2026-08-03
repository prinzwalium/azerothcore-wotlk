#!/bin/bash
set -e

echo "[AutoSetup] Bereite Konfigurationsdateien vor..."
CONF_DIR="/azerothcore/env/dist/etc"
DATA_DIR="/azerothcore/env/dist/data"
SQL_WORLD_DIR="/azerothcore/data/sql/base/db_world"

# Configs aus den Vorlagen erstellen
cp -n $CONF_DIR/worldserver.conf.dist $CONF_DIR/worldserver.conf 2>/dev/null || true
cp -n $CONF_DIR/authserver.conf.dist $CONF_DIR/authserver.conf 2>/dev/null || true

# Module-Configs automatisch vorbereiten
mkdir -p $CONF_DIR/modules
if ls $CONF_DIR/modules/*.conf.dist 1> /dev/null 2>&1; then
    for conf_dist in $CONF_DIR/modules/*.conf.dist; do
        conf_file="${conf_dist%.dist}"
        cp -n "$conf_dist" "$conf_file" 2>/dev/null || true
    done
fi

# Zugangsdaten eintragen
DB_PASS=${DB_PASSWORD:-"8BvjmZFexf9piYpqHKnIzIm5ysIXBbFwsDbao6qXJpQiSyzp8A13qoZ9sI1D5txm"}
sed -i "s/127.0.0.1;3306;acore;acore/ac-database;3306;root;${DB_PASS}/g" $CONF_DIR/worldserver.conf
sed -i "s/127.0.0.1;3306;acore;acore/ac-database;3306;root;${DB_PASS}/g" $CONF_DIR/authserver.conf
sed -i "s/127.0.0.1;3306;acore;acore/ac-database;3306;root;${DB_PASS}/g" $CONF_DIR/modules/playerbots.conf 2>/dev/null || true

# Den Pfad zu den Map-Daten in der Config anpassen
sed -i 's/^DataDir =.*/DataDir = "\/azerothcore\/env\/dist\/data"/g' $CONF_DIR/worldserver.conf

# --- Worldserver-exklusive Downloads ---
if [[ "$*" == *worldserver* ]]; then
    
    # 1. Map-Daten prüfen
    mkdir -p "$DATA_DIR"
    if [ -d "$DATA_DIR/dbc" ] && [ -d "$DATA_DIR/maps" ]; then
        echo "[AutoSetup] Map-Daten bereits vorhanden."
    elif [ -f "$DATA_DIR/data.zip" ]; then
        echo "[AutoSetup] data.zip gefunden! Entpacke Map-Daten..."
        unzip -q $DATA_DIR/data.zip -d $DATA_DIR && rm $DATA_DIR/data.zip
    elif [ -n "$MAP_DOWNLOAD_URL" ]; then
        echo "[AutoSetup] Lade Maps herunter..."
        curl -L -o $DATA_DIR/data.zip "$MAP_DOWNLOAD_URL"
        unzip -q $DATA_DIR/data.zip -d $DATA_DIR && rm $DATA_DIR/data.zip
    fi
    
   # 2. Base World Database prüfen
mkdir -p "$SQL_WORLD_DIR"

# Wenn der Ordner auf dem Volume leer ist, kopieren wir die SQL-Dateien aus dem Image dorthin
if [ -z "$(ls -A $SQL_WORLD_DIR 2>/dev/null)" ]; then
    echo "[AutoSetup] Kopiere World Base-DB aus dem Image..."
    cp -r /azerothcore/data/sql/base/db_world/* "$SQL_WORLD_DIR/"
else
    echo "[AutoSetup] World Base-DB bereits vorhanden."
fi
fi
# --------------------------------------------

echo "[AutoSetup] Configs bereit! Starte Server..."
exec "$@"
