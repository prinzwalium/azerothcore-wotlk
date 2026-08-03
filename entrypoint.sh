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

# --- NEU: Der intelligente Map-Downloader (NUR für den Worldserver) ---
if [[ "$*" == *worldserver* ]]; then
    mkdir -p "$DATA_DIR"
    
    # Stufe 1: Sind die entpackten Daten schon da?
    if [ -d "$DATA_DIR/dbc" ] && [ -d "$DATA_DIR/maps" ]; then
        echo "[AutoSetup] Map-Daten bereits entpackt vorhanden, überspringe Download."
    
    # Stufe 2: Liegt wenigstens die ZIP-Datei bereit?
    elif [ -f "$DATA_DIR/data.zip" ]; then
        echo "[AutoSetup] data.zip gefunden! Entpacke Map-Daten..."
        unzip -q $DATA_DIR/data.zip -d $DATA_DIR
        echo "[AutoSetup] Lösche Zip-Archiv..."
        rm $DATA_DIR/data.zip
        echo "[AutoSetup] Map-Daten erfolgreich installiert!"
        
    # Stufe 3: Nichts da. Gibt es eine Download-URL als ENV?
    elif [ -n "$MAP_DOWNLOAD_URL" ]; then
        echo "[AutoSetup] Map-Daten nicht gefunden! Lade von URL herunter: $MAP_DOWNLOAD_URL"
        curl -L -o $DATA_DIR/data.zip "$MAP_DOWNLOAD_URL"
        echo "[AutoSetup] Entpacke Map-Daten..."
        unzip -q $DATA_DIR/data.zip -d $DATA_DIR
        echo "[AutoSetup] Lösche Zip-Archiv..."
        rm $DATA_DIR/data.zip
        echo "[AutoSetup] Map-Daten erfolgreich installiert!"
        
    # Fallback: Keine Daten, keine ZIP, keine URL.
    else
        echo "[AutoSetup] WARNUNG: Keine Map-Daten, keine data.zip und keine MAP_DOWNLOAD_URL gefunden!"
        echo "[AutoSetup] Der Server wird versuchen ohne Maps zu starten (was wahrscheinlich fehlschlagen wird)."
    fi
fi
# --------------------------------------------

echo "[AutoSetup] Configs bereit! Starte Server..."

# Server-Befehl ausführen
exec "$@"
