Template to deploy dev environment with MariaDB/mySQL/Postgres, MongoDB, Redis, RabbitMQ, bind9 and nginx

```
Usage: init.sh [OPTIONS]
Options:
 -h --help          Display this message
 --docker           Use Docker and Docker Compose     DO NOT USE WITH --podman FLAG!
 --podman           Use Podman and Podman Compose     DO NOT USE WITH --docker FLAG!
 --mariadb          Use MariaDB as SQL database       DO NOT USE WITH --mysql   OR --postgres FLAG!
 --mysql            Use MySQL as SQL database         DO NOT USE WITH --mariadb OR --postgres FLAG!
 --postgres         Use PostgreSQL as SQL database    DO NOT USE WITH --mysql   OR --mariadb  FLAG!
```

`$ git clone git@github.com:Regeneric/scaffolding APP_NAME && cd APP_NAME`  
`$ bash init.sh`

or  

`$ bash init.sh --podman --mariadb`