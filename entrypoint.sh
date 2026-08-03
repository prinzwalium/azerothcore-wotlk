#!/bin/bash
set -e

echo "[AutoSetup] Bereite Konfigurationsdateien vor..."
CONF_DIR="/azerothcore/env/dist/etc"
DATA_DIR="/azerothcore/env/dist/data"
SQL_WORLD_DIR="/azerothcore/data/sql/base/db_world"

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
    # Wir prüfen auf eine DB-Datei, die > 100MB ist, oder einen spezifischen Präfix hat
    if ! ls $SQL_WORLD_DIR/acore-db-*.sql 1> /dev/null 2>&1; then
        echo "[AutoSetup] World Base-DB fehlt! Lade neuesten ACDB Dump über GitHub-API herunter..."
        DB_URL=$(curl -s https://api.github.com/repos/azerothcore/azerothcore-wotlk/releases/latest | grep "browser_download_url.*acore-db.*\.zip" | cut -d '"' -f 4)
        
        if [ -n "$DB_URL" ]; then
            curl -L -o acdb.zip "$DB_URL"
            unzip -q acdb.zip -d acdb_ext
            # Verschiebe die extrahierte SQL-Datei in den Auto-Updater Ordner
            find acdb_ext -name "*.sql" -exec mv {} $SQL_WORLD_DIR/ \;
            rm -rf acdb.zip acdb_ext
            echo "[AutoSetup] Base-DB erfolgreich für den Import bereitgestellt."
        else
            echo "[AutoSetup] Fehler: Konnte DB-URL nicht von GitHub abrufen."
        fi
    else
        echo "[AutoSetup] World Base-DB bereits vorhanden."
    fi
fi
# --------------------------------------------

echo "[AutoSetup] Configs bereit! Starte Server..."
exec "$@"
