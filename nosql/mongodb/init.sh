#!/usr/bin/env bash

# Prevent direct execution of this script. It should only be sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	echo "This is setup module and shouldn't be executed directly!"
	exit 1
fi

"$CONTAINER_APP" exec mongodb mongosh --authenticationDatabase admin -u root -p "${mongo_root_password}" --eval "$(cat nosql/mongodb/init/create_temp_admin.js)" admin
"$CONTAINER_APP" exec mongodb mongosh --authenticationDatabase admin -u "${mongo_user_name}" -p "${mongo_user_password}" --eval "$(cat nosql/mongodb/init/create_role.js)" admin
"$CONTAINER_APP" exec mongodb mongosh --authenticationDatabase admin -u "${mongo_user_name}" -p "${mongo_user_password}" --eval "$(cat nosql/mongodb/init/create_root.js)" admin
"$CONTAINER_APP" exec mongodb mongosh --authenticationDatabase admin -u "${mongo_user_name}" -p "${mongo_user_password}" --eval "$(cat nosql/mongodb/init/grant_role.js)"  admin
"$CONTAINER_APP" exec mongodb mongosh --authenticationDatabase admin -u "${mongo_user_name}" -p "${mongo_user_password}" --eval "$(cat nosql/mongodb/init/create_database.js)"