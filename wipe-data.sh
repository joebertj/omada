# names you’ll use for mounts
DATA_VOL=omada_data
LOGS_VOL=omada_logs

# delete if present (safe if they don't exist)
docker volume rm -f "$DATA_VOL" "$LOGS_VOL" 2>/dev/null || true

# create fresh empty volumes
docker volume create "$DATA_VOL"
docker volume create "$LOGS_VOL"

# run a fresh container using those volumes
docker run -d --name omada \
  -p 8088:8088 -p 8043:8043 \
  -v "$DATA_VOL":/opt/tplink/EAPController/data \
  -v "$LOGS_VOL":/opt/tplink/EAPController/logs \
  omada:5.15.24.19

# watch logs
docker logs -f omada

