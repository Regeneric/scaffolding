#!/usr/bin/env bash

# Prevent direct execution of this script. It should only be sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	echo "This is setup module and shouldn't be executed directly!"
	exit 1
fi

case "$SQL_DATABASE" in
  mysql) 
    container_name="mysql" 
    command_name="mysql"
  ;;
  mariadb) 
    container_name="mariadb" 
    command_name="mariadb"  
  ;;
  postgres) 
    container_name="postgres" 
    command_name="psql"
  ;;
esac

if [[ "$SQL_DATABASE" == "mysql" || "$SQL_DATABASE" == "mariadb" ]]; then
  "$CONTAINER_APP" exec "$container_name" "$command_name" -u root -p"${sql_root_password}" -e "CREATE USER '${sql_user_name}'@'%' IDENTIFIED BY '${sql_user_password}';"
  "$CONTAINER_APP" exec "$container_name" "$command_name" -u root -p"${sql_root_password}" -e "GRANT ALL PRIVILEGES ON *.* TO '${sql_user_name}'@'%';"
  "$CONTAINER_APP" exec "$container_name" "$command_name" -u root -p"${sql_root_password}" -e "FLUSH PRIVILEGES;"
  "$CONTAINER_APP" exec "$container_name" "$command_name" -u root -p"${sql_root_password}" -e "CREATE DATABASE ${sql_database_name};"
else
  PGPASSWORD="$sql_root_password"
  export PGPASSWORD

  "$CONTAINER_APP" exec "$container_name" "$command_name" -U postgres -c "CREATE USER ${sql_user_name} WITH PASSWORD ${sql_user_password};"
  "$CONTAINER_APP" exec "$container_name" "$command_name" -U postgres -c "CREATE DATABASE ${sql_database_name};"
  "$CONTAINER_APP" exec "$container_name" "$command_name" -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE ${sql_database_name} TO ${sql_user_name};"

  unset PGPASSWORD
fi