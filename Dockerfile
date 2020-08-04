FROM cloudflare/cloudflared
FROM debian:latest
COPY --from=0 /usr/local/bin/cloudflared /bin/cloudflared

ENTRYPOINT ["/bin/bash", "-c", "/bin/cloudflared tunnel --metrics 0.0.0.0:32803 --hostname $HOSTNAME --url $ORIGIN --origincert <(echo \"$CERTPEM\")"]