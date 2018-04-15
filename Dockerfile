FROM alpine:3.7

# alpine includes "postgres" user/group in base install
#   /etc/passwd:22:postgres:x:70:70::/var/lib/postgresql:/bin/sh
#   /etc/group:34:postgres:x:70:
# the home directory for the postgres user, however, is not created by default
# see https://github.com/docker-library/postgres/issues/274
RUN set -ex; \
	postgresHome="$(getent passwd postgres)"; \
	postgresHome="$(echo "$postgresHome" | cut -d: -f6)"; \
	[ "$postgresHome" = '/var/lib/postgresql' ]; \
	mkdir -p "$postgresHome"; \
	chown -R postgres:postgres "$postgresHome"
	
	
# make the "en_US.UTF-8" locale so postgres will be utf-8 enabled by default
# alpine doesn't require explicit locale-file generation
ENV LANG en_US.utf8

# JDK Setup for Hadoop Extension
ENV LDFLAGS="-L/usr/lib/jvm/java-1.8-openjdk/jre/lib/amd64/server"
ENV CFLAGS="-I/usr/lib/jvm/java-1.8-openjdk/include"
ENV LD_LIBRARY_PATH=/usr/lib/jvm/java-1.8-openjdk/jre/lib/amd64/server:$LD_LIBRARY_PATH 
ENV PATH=/usr/lib/jvm/java-1.8-openjdk/bin/:$PATH

RUN set -ex \
	\
	&& apk add --no-cache --virtual .fetch-deps \
		ca-certificates \
		openssl \
		tar \
		openjdk8 \
		zlib \
		git  \
	\
	&& apk add --no-cache --virtual .build-deps \
		openssl-dev \
		build-base \
		linux-headers \
		perl \
		perl-utils \
		perl-ipc-run \
		readline-dev \
		zlib-dev \
   		libxml2 libxml2-dev \
   		libxslt libxslt-dev \
   		flex \
   		bison\
   \
   && git clone https://github.com/bitnine-oss/agensgraph.git \
   && cd agensgraph \
   \ 
   && ./configure \
        --prefix=$(pwd) \
   		--enable-integer-datetimes \
		--enable-thread-safety \
		--enable-tap-tests \
# skip debugging info -- size!
#		--enable-debug \
		--disable-rpath \
		--with-gnu-ld \
		--with-pgport=5432 \
		--with-system-tzdata=/usr/share/zoneinfo \
		--prefix=/usr/local \
		--with-includes=/usr/local/include,/usr/lib/jvm/java-1.8-openjdk/include \
		--with-libraries=/usr/local/lib,/usr/lib/jvm/java-1.8-openjdk/jre/lib/amd64/server \
		--with-openssl \
		--with-libxml \
		--with-libxslt \
		\
	&& make install \
	&& make install-world \
    && make -C contrib install \
	\
	&& runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
		)" \
	&& apk add --no-cache --virtual .postgresql-rundeps \
		$runDeps \
		bash \
		su-exec \
		tzdata \
	## Remove build deps and stuff
	&& apk del .fetch-deps .build-deps \
	&& cd / \
	&& rm -rf \
		/agensgraph \
		/usr/local/share/doc \
		/usr/local/share/man \
	&& find /usr/local -name '*.a' -delete


# Data storage
ENV AGDATA=/var/lib/agensgraph/data
# this 777 will be replaced by 700 at runtime (allows semi-arbitrary "--user" values)
RUN mkdir -p "$AGDATA" && chown -R postgres:postgres "$AGDATA" && chmod 777 "$AGDATA" 

VOLUME /var/lib/agensgraph/data


COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY agens-graph /usr/local/bin/agens-graph
RUN chmod +x /usr/local/bin/entrypoint.sh && \
    chmod +x /usr/local/bin/agens-graph && \
    ln -s /usr/local/bin/entrypoint.sh /entrypoint.sh # backwards compat

ENTRYPOINT ["entrypoint.sh"]
EXPOSE 5432
CMD ["agens-graph"]
