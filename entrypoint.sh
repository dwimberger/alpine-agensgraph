#!/usr/bin/env bash
set -e

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}
if [ "${1:0:1}" = '-' ]; then
	set -- postgres "$@"
fi
# allow the container to be started with `--user`
if [ "$1" = 'agens-graph' ] && [ "$(id -u)" = '0' ]; then
	mkdir -p "$AGDATA"
	chown -R postgres "$AGDATA"
	chmod 700 "$AGDATA"

	mkdir -p /var/run/postgresql
	chown -R postgres /var/run/postgresql
	chmod 775 /var/run/postgresql

	# Create the transaction log directory before initdb is run (below) so the directory is owned by the correct user
	if [ "$POSTGRES_INITDB_WALDIR" ]; then
		mkdir -p "$POSTGRES_INITDB_WALDIR"
		chown -R postgres "$POSTGRES_INITDB_WALDIR"
		chmod 700 "$POSTGRES_INITDB_WALDIR"
	fi

	echo su-exec postgres "$BASH_SOURCE" "$@"
	exec su-exec postgres "$BASH_SOURCE" "$@"
fi
if [ "$1" = 'agens-graph' ]; then
	mkdir -p "$AGDATA"
	chown -R "$(id -u)" "$AGDATA" 2>/dev/null || :
	chmod 700 "$AGDATA" 2>/dev/null || :

	# look specifically for PG_VERSION, as it is expected in the DB dir
	if [ ! -s "$AGDATA/PG_VERSION" ]; then
		file_env 'POSTGRES_INITDB_ARGS'
		if [ "$POSTGRES_INITDB_WALDIR" ]; then
			export POSTGRES_INITDB_ARGS="$POSTGRES_INITDB_ARGS --waldir $POSTGRES_INITDB_WALDIR"
		fi
		eval "initdb --username=postgres $POSTGRES_INITDB_ARGS"

		# check password first so we can output the warning before postgres
		# messes it up
		file_env 'GRAPH_PASSWORD'
		if [ "$GRAPH_PASSWORD" ]; then
			pass="PASSWORD '$GRAPH_PASSWORD'"
			authMethod=md5
		else
			# The - option suppresses leading tabs but *not* spaces. :)
			echo "WARNING: No password has been set for the database."
			pass=
			authMethod=trust
		fi

		{
			echo
			echo "host all all all $authMethod"
		} >> "$AGDATA/pg_hba.conf"

		# internal start of server in order to allow set-up using psql-client
		# does not listen on external TCP/IP and waits until start finishes
		PGUSER="${PGUSER:-postgres}" \
		ag_ctl -D "$AGDATA" \
			-o "-c listen_addresses='localhost'" \
			-w start

		file_env 'GRAPH_USER' 'postgres'
		file_env 'GRAPH_DB' "$GRAPH_USER"

		agens=( agens -v ON_ERROR_STOP=1 )

		if [ "$GRAPH_DB" != 'postgres' ]; then
			"${agens[@]}" --username postgres <<-EOSQL
				CREATE DATABASE "$GRAPH_DB" ;
			EOSQL
			echo
		fi

		if [ "$GRAPH_USER" = 'postgres' ]; then
			op='ALTER'
		else
			op='CREATE'
		fi
		"${agens[@]}" --username postgres <<-EOSQL
			$op USER "$GRAPH_USER" WITH SUPERUSER $pass ;
		EOSQL
		echo
		"${agens[@]}" --username postgres <<-EOSQL
			CREATE GRAPH docker_graph;
		EOSQL

		agens+=( --username "$GRAPH_USER" --dbname "$GRAPH_DB" )

		echo
		for f in /docker-entrypoint-initdb.d/*; do
			case "$f" in
				*.sh)     echo "$0: running $f"; . "$f" ;;
				*.sql)    echo "$0: running $f"; "${psql[@]}" -f "$f"; echo ;;
				*.sql.gz) echo "$0: running $f"; gunzip -c "$f" | "${agens[@]}"; echo ;;
				*)        echo "$0: ignoring $f" ;;
			esac
			echo
		done

		PGUSER="${PGUSER:-postgres}" \
		ag_ctl -D "$AGDATA" -m fast -w stop
		sed -ri "s!^#?(listen_addresses)\s*=\s*\S+.*!\1 = '*'!" $AGDATA/postgresql.conf

		echo
		echo 'AgensGraph init process complete; ready for start up.'
		echo
	fi
fi

exec "$@"