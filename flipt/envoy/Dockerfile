FROM envoyproxy/envoy:v1.38.3

COPY envoy.yaml.tmpl /etc/envoy/envoy.yaml.tmpl
COPY render-config.sh /usr/local/bin/render-config.sh
RUN chmod +x /usr/local/bin/render-config.sh

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/render-config.sh"]
CMD ["envoy", "-c", "/etc/envoy/envoy.yaml", "--service-cluster", "flipt-grpcweb", "-l", "info"]
