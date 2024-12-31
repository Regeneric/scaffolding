#!/usr/bin/env bash

# Prevent direct execution of this script. It should only be sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	echo "This is setup module and shouldn't be executed directly!"
	exit 1
fi

"$CONTAINER_APP" exec -i rabbitmq rabbitmqctl add_user "$rabbitmq_user_name" "$rabbitmq_user_password"
"$CONTAINER_APP" exec -i rabbitmq rabbitmqctl set_permissions "$rabbitmq_user_name" ".*" ".*" ".*"
"$CONTAINER_APP" exec -i rabbitmq rabbitmqctl set_user_tags "$rabbitmq_user_name" administrator
"$CONTAINER_APP" exec -i rabbitmq rabbitmq-plugins enable rabbitmq_management
"$CONTAINER_APP" exec -i rabbitmq rabbitmqctl delete_user guest