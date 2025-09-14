docker run -d --name omada \
  --platform=linux/amd64 \
  -p 8043:8043 -p 8088:8088 \
  -p 27001:27001/udp -p 27002:27002 \
  -p 29810:29810/udp -p 29811:29811 -p 29812:29812 -p 29813:29813 \
  -v omada-data:/opt/tplink/EAPController/data \
  -v omada-logs:/opt/tplink/EAPController/logs \
  --restart unless-stopped \
  omada:5.15.24.19

