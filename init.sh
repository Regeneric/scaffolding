#!/usr/bin/env bash

# Set PATH variable to include standard binary directories
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

BASENAME=$(basename "${0%%.sh}")						            # Extract the script's base name
DIR=$(dirname $(realpath "$0"))							            # Get the directory of the script
HOSTNAME=$(hostname -s | tr '[:upper:]' '[:lower:]')	  # Convert hostname to lowercase
DISTRO=$(awk -F= '/^ID=/{print $2}' /etc/os-release)	  # Detect the Linux distribution
LOG_DIR="${DIR}/logs/setup"
TERMINAL_HEIGHT=$(tput lines)							              # Fetch the terminal height for dynamic dialog adjustments

# Recommended minimum system requirements - based on what I think should be enough
RECOMMENDED_CPU_CORES=8
RECOMMENDED_MEMORY_GB=16
RECOMMENDED_DISK_SPACE_GB=50

# Regular expressions for validating user login and password
VALID_USERNAME_REGEX="^[a-zA-Z][a-zA-Z0-9_]*$"
VALID_PASSWORD_REGEX="^[a-zA-Z0-9_@#\$%\!\^&*()-+=-]+$"

DOCKER_ENV_FILE_LOCATION="config/docker.env"
CONTAINER_APP=""
SQL_DATABASE=""

# Define Docker authentication paths based on the detected distribution
case "${DISTRO}" in
	ubuntu)
	  DOCKER_AUTH_DIR="/run/containers/$(id -u)"
	;;
	debian)
		DOCKER_AUTH_DIR="/run/user/$(id -u)/containers"
	;;
esac


###############################################################################
# -- FUNCTIONS
# -----------------------------------------------------------------------------
# -- UTILS
# -----------------------------------------------------------------------------

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo " -h --help          Display this message"
  echo " --docker           Use Docker and Docker Compose"
  echo " --podman           Use Podman and Podman Compose"
  echo " --mariadb          Use MariaDB as SQL database"
  echo " --mysql            Use MySQL as SQL database"
  echo " --postgres         Use PostgreSQL as SQL database"
}

# Like: --my --ass -i -s --fucking-awesome
handle_flags() {
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help)
        usage
        exit 1
      ;;
      --docker)
        CONTAINER_APP="docker"
        shift
      ;;
      --podman)
        CONTAINER_APP="podman"
        shift
      ;;
      --mariadb)
        SQL_DATABASE="mariadb"
        shift
      ;;
      --mysql)
        SQL_DATABASE="mysql"
        shift
      ;;
      --postgres)
        SQL_DATABASE="postgres"
        shift
      ;;
      *)
        usage
        exit 1
      ;;
    esac
  done
}

idate() {
  date +"%Y-%m-%d %H:%M:%S"
}

log() {
  if [[ ! -d "$LOG_DIR" ]]; then
    mkdir -p "$LOG_DIR"
    LOG=$(mktemp "$LOG_DIR/${BASENAME}_log-XXXXXXXX")				# Create a temporary log file
  fi

  if [[ ! -s "$LOG" ]]; then
    echo "[$(idate)] $1" > "$LOG"
  else
    echo "[$(idate)] $1" >> "$LOG"
  fi
}

spacer() {
  local spaces=""
  for ((i=0; i<"$1"; i++)); do spaces+=" "; done
  echo -n "$spaces"
}

dialog_wait() {
	local msg=$1
	dialog --title "Please wait" --infobox "${msg}..." 3 36
}

dialog_input() {
  local r=""
  if [[ "$3" == "password" || "$3" == "pass" || "$3" == "pwd" ]]; then
    r=$(dialog --title "$1" --insecure --passwordbox "$2" 9 32 "${r}" 3>&1 1>&2 2>&3 3>&-)
  else
    r=$(dialog --title "$1" --inputbox "$2" 9 32 "${r}" 3>&1 1>&2 2>&3 3>&-)
  fi

  echo "$r"
}

install_missing_software() {
  local packages=("$@")
  local num_packages=${#packages[@]}
  local sudo_pwd=$(dialog --title "sudo credentials" --insecure --passwordbox "Enter sudo password" 8 40 "${sudo_pwd}" 3>&1 1>&2 2>&3 3>&-)

  case "${DISTRO}" in
    ubuntu | debian | linuxmint | pop | elementary)
      clear
      echo "$sudo_pwd" | sudo apt update 
      echo "$sudo_pwd" | sudo apt install -y "${packages[@]}"

      if [[ "$?" -ne 0 ]]; then
        log "Couldn't install one or more packages - ${packages[@]}"
        exit 1
      fi
    ;;
    arch | manjaro)
      if ! check_package yay; then
        dialog --title "Software Install" --msgbox "\nCouldn't find 'yay' package manager. Please install it manually.\nThen run this configurator again.\n" 8 70
        log "Couldn't install ${packages[@]} - missing 'yay' package manager"
        clear
        exit 1
      fi

      clear
      echo "$sudo_pwd" | sudo pacman -S --noconfirm "${packages[@]}"

      if [[ "$?" -ne 0 ]]; then
        log "Couldn't install one or more packages - ${packages[@]}"
        exit 1
      fi
    ;;
    fedora | centos | rhel)
      clear
      echo "$sudo_pwd" | sudo dnf install -y "${packages[@]}"

      if [[ "$?" -ne 0 ]]; then
        log "Couldn't install one or more packages - ${packages[@]}"
        exit 1
      fi
    ;;
    suse | opensuse | opensuse-leap)
      clear
      echo "$sudo_pwd" | sudo zypper refresh
      echo "$sudo_pwd" | sudo zypper install -y "${packages[@]}"

      if [[ "$?" -ne 0 ]]; then
        log "Couldn't install one or more packages - ${packages[@]}"
        exit 1
      fi
    ;;
    *)
      if [[ "$num_packages" -gt 5 ]]; then
        dialog --title "Software Install" --msgbox "\nCouldn't verify your OS distribution ($DISTRO). Please manually install ${packages[@]:0:5} and $((num_packages - 5)) more packages.\nThen run this configurator again.\n" 8 70
      else
        dialog --title "Software Install" --msgbox "\nCouldn't verify your OS distribution ($DISTRO). Please manually install: ${packages[@]}.\nThen run this configurator again.\n" 8 70
      fi

      log "Couldn't install ${packages[@]} - unkown distribution $DISTRO"
      clear
      exit 1
    ;;
  esac

  log "Packages ${packages[@]} have been installed"
  sudo_pwd=""
}

trap_int() {
	clear
	tput cnorm
	log "CTRL+C pressed. Cleaning and exiting"
	# cleanup
	exit 0
}

check_package() {
  if command -v "$1" >/dev/null 2>&1; then
    log "Package $1 has been found"
    return 0
  else return 1; fi 
}

# -----------------------------------------------------------------------------
# -- CONTAINERS
# -----------------------------------------------------------------------------


# Check if Docker is installed
check_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker has been found"
    return 0
  else return 1; fi
}

check_docker_compose() {
  if command -v docker-compose >/dev/null 2>&1; then
    log "Docker Compose has been found"
    return 0
  else return 1; fi
}

# Check if Podman is installed
check_podman() {
  if command -v podman >/dev/null 2>&1; then
    log "Podman has been found"
    return 0
  else return 1; fi
}

check_podman_compose() {
  if command -v podman-compose >/dev/null 2>&1; then
    log "Podman Compose has been found"
    return 0
  else return 1; fi
}

check_env_file() {
  if [[ -f "$DOCKER_ENV_FILE_LOCATION" ]]; then 
    log "Found docker.env file at $DOCKER_ENV_FILE_LOCATION"
    return 0;
  else return 1; fi
}

start_container() {
  local cp=$(pwd)

  if [[ "$(${CONTAINER_APP} ps -aqf name=${1})" ]]; then
    ${CONTAINER_APP} rm -f ${1}
    ${CONTAINER_APP}-compose --env-file ${cp}/config/docker.env -f ${cp}/docker/compose.yml up -d ${1}
  else
    ${CONTAINER_APP}-compose --env-file ${cp}/config/docker.env -f ${cp}/docker/compose.yml up -d ${1}
  fi

  if [[ "$?" -eq 0 ]]; then
    log "Container ${1} has started"
  else
    log "Container ${1} failed to start"
    exit 1
  fi
}


main() {
  if [[ ! -d "config" ]]; then mkdir config; fi
  if [[ -f "config/init.lock" ]]; then
    dialog --title "RUN IT ONLY ONCE" --msgbox "\n$(spacer 4)THIS CONFIGURATION TOOL IS DESIGNED TO BE RUN ONLY ONCE!\n" 8 69
    clear
    exit 1
  fi

  log "Configuration has started"
  touch config/init.lock

  if ! check_package "sudo"; then
    install_missing_software "sudo"
    if [[ $? -eq 0 ]]; then 
      log "Package sudo has been installed"
    else
      log "Failed to install package sudo"
      clear
      exit 1
    fi
  fi

  if ! check_package "dialog"; then
    install_missing_software "dialog"
    if [[ $? -eq 0 ]]; then
      log "Package dialog has been installed"
    else
      log "Failed to install package dialog"
      clear
      exit 1
    fi
  fi

  dialog --title "hkk's scaffolding" --msgbox "\n$(spacer 12)Welcome to the hkk's configuration tool.\n$(spacer 4)It'll setup dev environment for you (SQL, noSQL, DNS etc.)\n" 8 69


  ###############################################################################
  # -- CONTAINERIZATION 
  # -----------------------------------------------------------------------------

  # If CONTAINER_APP variable isn't set check for Docker/Podman
  if [[ -z "$CONTAINER_APP" ]]; then
    if check_docker; then 
      local docker_installed="true";
      local docker_path=$(which docker)
      CONTAINER_APP="docker"

      log "Docker is installed at $docker_path"

      if check_docker_compose; then
        local docker_compose_path=$(which docker-compose) 
        log "Docker Compose is installed at $docker_compose_path"
      else
        install_missing_software "docker-compose"
      fi
    fi
    
    if check_podman; then 
      local podman_installed="true"; 
      local podman_path=$(which podman)
      CONTAINER_APP="podman"

      log "Podman is installed at $podman_path"

      if check_podman_compose; then
        local podman_compose_path=$(which podman-compose) 
        log "Podman Compose is installed at $podman_compose_path"
      else
        install_missing_software "podman-compose"
      fi
    fi

    # Both Podman and Docker ARE installed, so the user must decide
    if [[ "$docker_installed" == "true" && "$podman_installed" == "true" ]]; then
      local response=$(dialog --title "Containerization Software" --menu "Select the package you want to use\n" 10 32 6 1 "Docker" 2 "Podman" 3>&1 1>&2 2>&3)
      if [[ "$response" -eq 1 ]]; then CONTAINER_APP="docker"
      else CONTAINER_APP="podman"; fi
    fi
    
    # Both Podman and Docker ARE NOT installed, so the user must decide
    if [[ "$docker_installed" != "true" && "$podman_installed" != "true" ]]; then
      local response=$(dialog --title "Containerization Software" --menu "Select the package you want to use\n" 10 32 6 1 "Docker" 2 "Podman" 3>&1 1>&2 2>&3)
      if [[ "$response" -eq 1 ]]; then CONTAINER_APP="docker"
      else CONTAINER_APP="podman"; fi

      install_missing_software "$CONTAINER_APP" "podman-compose"
    fi
  fi

  # Check if user canceled the installation
  if [[ "$response" -eq 1 ]]; then
    clear
    log "Config process has been canceled by user"
    exit 0
  fi

  log "$CONTAINER_APP package will be used for containerization"


  if check_env_file; then 
    dialog --title "Config File" --yesno "\n$(spacer 8)File config/docker.env is already present\n$(spacer 14)Would you like to remove it?\n" 8 60
    response=$?

    # Ask again if user said YES
    if [[ "$response" -eq 0 ]]; then
      dialog --title "Config File" --yesno "\n$(spacer 10)Are you sure?\n" 7 40
      response=$?
    fi

    if [[ "$response" -eq 0 ]]; then
      rm -f "$DOCKER_ENV_FILE_LOCATION"
      log "Config file at $DOCKER_ENV_FILE_LOCATION has been removed"
    else 
      clear
      log "Config process has been aborted: $DOCKER_ENV_FILE_LOCATION already exists"
      exit 0
    fi


    # User pressed ESC key
    if [[ "$response" -eq 255 ]]; then
      clear
      log "Config process has been canceled by user"
      exit 0
    fi
  fi

  # -----------------------------------------------------------------------------
  # -- CONFIG FILE
  # -----------------------------------------------------------------------------

  if [[ -z "$SQL_DATABASE" ]]; then
    response=$(dialog --title "SQL Database" --menu "Select the package you want to use\n" 11 32 6 1 "MySQL" 2 "MariaDB" 3 "PostgreSQL" 3>&1 1>&2 2>&3)
    case "$response" in
      1) SQL_DATABASE="mysql" ;;
      2) SQL_DATABASE="mariadb" ;;
      3) SQL_DATABASE="postgres" ;;
    esac

    # if [[ "$?" -eq 0 ]]; then
    #   clear
    #   log "Config process has been canceled by user"
    #   exit 0
    # fi
  fi
  log "Selected $SQL_DATABASE as SQL databse"
  
  find sql -mindepth 1 -maxdepth 1 -type d ! -name "$SQL_DATABASE" -exec rm -rf {} +
  log "Other SQL database directories have been removed"
  
  if [[ ! -d "sql/$SQL_DATABASE/data" ]]; then 
    mkdir -p sql/$SQL_DATABASE/data; 
    log "Directory sql/$SQL_DATABASE/data has been created"  
  fi

  if [[ ! -d "sql/$SQL_DATABASE/backup" ]]; then 
    mkdir -p sql/$SQL_DATABASE/backup; 
    log "Directory sql/$SQL_DATABASE/backup has been created"  
  fi

  local source_code_location=$(dialog_input "General Config" "Source code location")
  local domain_name=$(dialog_input "General Config" "Enter domain name")
  local internal_ip=$(dialog_input "General Config" "Enter internal IP (CIDR)")
  local external_ip=$(dialog_input "General Config" "Enter external IP (CIDR)")

  dialog --title "General Config" --yesno "\n$(spacer 3)Would you like to run services on the internal IP?\n" 8 60
  response=$?

  if [[ "$response" -eq 0 ]]; then
    local sql_host="${internal_ip%/*}"
    local mongo_host="${internal_ip%/*}"
    local rabbit_host="${internal_ip%/*}"
    local redis_host="${internal_ip%/*}"
  else
    local sql_host=$(dialog_input "Database Definition" "Enter SQL host")
    local mongo_host=$(dialog_input "Database Definition" "Enter MongoDB host")
    local rabbit_host=$(dialog_input "Database Definition" "Enter RabbitMQ host")
    local redis_host=$(dialog_input "Database Definition" "Enter Redis host")
  fi

  local sql_database_name=$(dialog_input "SQL Credentials" "Enter SQL database name")
  local sql_user_name=$(dialog_input "SQL Credentials" "Enter SQL user name")
  local sql_user_password=$(dialog_input "SQL Credentials" "Enter SQL user password" "password")
  local sql_root_password=$(dialog_input "SQL Credentials" "Enter SQL root password" "password")

  local mongo_database_name=$(dialog_input "MongoDB Credentials" "Enter MongoDB database name")
  local mongo_user_name=$(dialog_input "MongoDB Credentials" "Enter MongoDB user name")
  local mongo_user_password=$(dialog_input "MongoDB Credentials" "Enter MongoDB user password" "password")
  local mongo_root_password=$(dialog_input "MongoDB Credentials" "Enter MongoDB root password" "password")

  local rabbitmq_user_name=$(dialog_input "RabbitMQ Credentials" "Enter RabbitMQ user name")
  local rabbitmq_user_password=$(dialog_input "RabbitMQ Credentials" "Enter RabbitMQ user password" "password")

  local redis_user_password=$(dialog_input "Redis Credentials" "Enter Redis user password" "password")


  local current_path=$(pwd)
  cat << EOF > "$DOCKER_ENV_FILE_LOCATION"
  ENV_FILE=${current_path}/config/docker.env

  CONFIG_FOLDER=${current_path}
  NGINX_CONF_LOCATION=${current_path}/nginx
  BIND_CONF_LOCATION=${current_path}/bind9
  SOURCE_CODE_LOCATION=${current_path}/${source_code_location}

  DOMAIN_NAME=${domain_name}

  INTERNAL_IP=${internal_ip%/*}
  INTERNAL_MASK=${internal_ip##*/}

  EXTERNAL_IP=${external_ip%/*}
  EXTERNAL_MASK=${external_ip##*/}

  SQL_USER=${sql_user_name}
  SQL_PASS=${sql_user_password}
  SQL_ROOT_PASS=${sql_root_password}
  SQL_HOST=${sql_host}
  SQL_PORT=3306
  SQL_DATABASE_NAME=${sql_database_name}

  MONGO_USER=root
  MONGO_PASS=${mongo_user_password}
  MONGO_ROOT_PASS=${mongo_root_password}
  MONGO_HOST=${mongo_host}
  MONGO_PORT=27017
  MONGO_DATABASE_NAME=${mongo_database_name}
  MONGO_REPL_SET_NAME=mongoreplicaset1
  MONGO_INITDB_USER=${mongo_user_name}
  MONGO_INITDB_NAME=admin

  RABBIT_USER=${rabbitmq_user_name}
  RABBIT_PASS=${rabbitmq_user_password}
  RABBIT_HOST=${rabbit_host}

  REDIS_PASS=${redis_user_password}
  REDIS_HOST=${redis_host}
  REDIS_PORT=6379
EOF
  log "File $DOCKER_ENV_FILE_LOCATION has been created"


  ###############################################################################
  # -- NOSQL 
  # -----------------------------------------------------------------------------

  local mongo_data_dir="nosql/mongodb/data"
  if [[ ! -d "$mongo_data_dir" ]]; then 
    mkdir -p "$mongo_data_dir" 
    log "Directory $mongo_data_dir has been created"  
  fi

  local mongo_backup_dir="nosql/mongodb/backup"
  if [[ ! -d "$mongo_backup_dir" ]]; then 
    mkdir -p "$mongo_backup_dir" 
    log "Directory $mongo_backup_dir has been created"  
  fi


  local mongo_conf_file="nosql/mongodb/mongod.conf"
  cat << EOF > "$mongo_conf_file"
  storage:
    directoryPerDB: true
    journal:
      enabled: true
    wiredTiger:
      engineConfig:
        cacheSizeGB: 1
  security:
    authorization: enabled
    keyFile: /data/db/keyFile
  net:
    port: 27017
    bindIp: 127.0.0.1,${internal_ip}
EOF
  log "File $mongo_conf_file has been created"

  local mongo_create_temp_admin_file="nosql/mongodb/init/create_temp_admin.js"
  cat << EOF > "$mongo_create_temp_admin_file"
  db.createUser({
      user: '${mongo_user_name}',
      pwd: '${mongo_user_password}',
      roles: [{role: 'root', db: 'admin'}]
  });
EOF
  log "File $mongo_create_temp_admin_file has been created"

  local mongo_create_root_file="nosql/mongodb/init/create_root.js"
  cat << EOF > "$mongo_create_root_file"
  db.createUser({
      user: "root",
      pwd: "${mongo_root_password}",
      roles: [{role: "remote_role", db: "admin"}],
  });
EOF
  log "File $mongo_create_root_file has been created"

  local mongo_setup_replicaset_file="nosql/mongodb/init/setup_replicaset.js"
  cat << EOF > "$mongo_setup_replicaset_file"
  rs.initiate({
      _id: "mongoreplicaset1",
      version: 1,
      members: [{ _id: 0, host : "mongo-mongo1.${domain_name}:27017"}]
  });
EOF
  log "File $mongo_setup_replicaset_file has been created"

  local mongo_create_database_file="nosql/mongodb/init/create_database.js" 
  cat << EOF > "$mongo_create_database_file"
  db = db.getSiblingDB('${mongo_database_name}');
EOF
  log "File $mongo_create_database_file has been created"


  openssl rand -base64 756 > nosql/mongodb/keyFile
  log "File nosql/mongodb/keyFile has been created"

  sudo chown $(whoami):$(whoami) nosql/mongodb/init.sh
  sudo chown -R $(whoami):$(whoami) nosql/mongodb/init
  sudo chown -R 1001:$(whoami) nosql/mongodb/data
  sudo chown -R 1001:$(whoami) nosql/mongodb/backup
  sudo chown 1001:$(whoami) nosql/mongodb/keyFile
  sudo chmod 400 nosql/mongodb/keyFile

  log "Permissions for MongoDB files and directories have been set"

  clear
  start_container "mongodb"
  sleep 15

  . nosql/mongodb/init.sh
  if [[ "$?" -eq 0 ]]; then
    log "MongoDB init success"
  else
    log "MongoDB init failure"
    exit 1
  fi

  clear
  start_container "redis"


  ###############################################################################
  # -- SQL 
  # -----------------------------------------------------------------------------

  clear
  start_container "$SQL_DATABASE"
  sleep 15

  . sql/init.sh
  if [[ "$?" -eq 0 ]]; then
    log "$SQL_DATABASE init success"
  else
    log "$SQL_DATABASE init failure"
    exit 1
  fi


  ###############################################################################
  # -- RABBITMQ 
  # -----------------------------------------------------------------------------

  clear
  start_container "rabbitmq"
  sleep 15

  . rabbitmq/init.sh
  if [[ "$?" -eq 0 ]]; then
    log "RabbitMQ init success"
  else
    log "RabbitMQ init failure"
    exit 1
  fi


  ###############################################################################
  # -- REVERSE PROXY 
  # -----------------------------------------------------------------------------

  local nginx_sites_dir="nginx/sites"
  if [[ ! -d "$nginx_sites_dir" ]]; then 
    mkdir -p "$nginx_sites_dir" 
    log "Directory $nginx_sites_dir has been created"  
  fi

  local nginx_ssl_dir="nginx/ssl"
  if [[ ! -d "$nginx_ssl_dir" ]]; then 
    mkdir -p "$nginx_ssl_dir" 
    log "Directory $nginx_ssl_dir has been created"  
  fi


  cat << EOF > "${nginx_sites_dir}/${domain_name}.conf"
  upstream 11b9509-6783478-bb37b70-f2617d0 {
          server ${internal_ip}:8989;
  }
  server {
      listen              ${external_ip}:443 ssl ;
      server_name         ${domain_name};
      ssl_certificate     /etc/ssl/certs/${domain_name}.crt;
      ssl_certificate_key /etc/ssl/private/${domain_name}.key;
      ssl_protocols       TLSv1 TLSv1.1 TLSv1.2;
      ssl_ciphers         HIGH:!aNULL:!MD5;

      location / {
          proxy_pass http://11b9509-6783478-bb37b70-f2617d0;
          proxy_set_header Host \$host;
          proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      }
  }
EOF
  log "File ${nginx_sites_dir}/${domain_name}.conf has been created"

  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout nginx/ssl/${domain_name}.key -out nginx/ssl/${domain_name}.crt
  clear
  start_container "reverse_proxy"


  ###############################################################################
  # -- DNS 
  # -----------------------------------------------------------------------------

  local current_date=$(date +%Y%m%d)
  local zone_name="db.$domain_name"

  cat << EOF > bind9/${zone_name}
  \$TTL 300
  @       IN     SOA    ns1.${domain_name}. root.${domain_name}. (
                        ${current_date}00 ; serial
                        300            ; refresh, seconds
                        300            ; retry, seconds
                        300            ; expire, seconds
                        300 )          ; minimum TTL, seconds

  @       IN     NS     ns1.${domain_name}.
  ns1     IN      A     ${internal_ip}

  ${domain_name}      IN A ${internal_ip};
  *.${domain_name}    IN A ${internal_ip};
EOF
  log "File bind9/${zone_name} has been created"

  local bind_access_network_file="bind9/named.conf.access_network"
  cat << EOF > "$bind_access_network_file"
  zone "${domain_name}" IN {
      type master;
      file "${zone_name}";
      allow-update { none; };
  };
EOF
  log "File $bind_access_network_file has been created"

  clear
  start_container "dns"
}

handle_flags "$@"
main "$#"
clear