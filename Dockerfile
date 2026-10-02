FROM manyfold3d/manyfold-solo:0.146.0@sha256:4e9ce8b600f0d9106afdfd6b1ea78b325db32e46471f7de62c1aa9cc0b4e7d35

COPY docker/local-setup.rb /usr/src/app/docker/local-setup.rb
RUN sed -i '/^bundle exec rails db:prepare:with_data$/a bundle exec rails runner docker/local-setup.rb' /usr/src/app/bin/docker-entrypoint.sh

ENTRYPOINT ["/bin/ash", "-ec", "mkdir -p /config/models; chown $PUID:$PGID /config /config/models; exec /init"]
