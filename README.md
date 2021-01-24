## Dump and restore scripts for MySQL database

### Chosen stack:
1. mysqldump for MySQL backup; mysql client for restore
2. AWS S3 for remote backup storage
3. Bash for scripting
4. Golang as a simple mean to implement a very lightweight smtp client

### Method of procedure:
1. Download the repository to your MySQL server
2. Fill out the configuration file **".config.sh"** which should be on the same level with **"restore.sh"** and **"backup.sh"** scripts (some fields are already filled):
    ```
    mysql_host="localhost"
    mysql_port="3306"
    mysql_user="root"
    mysql_password=""
    mysql_db_name=""
    mysql_socket="/var/run/mysqld/mysqld.sock"
    mysql_bin="$(which mysql)"
    mysql_dump_bin="$(which mysqldump)"
    mysql_connect_conf="$(pwd)/.my.cnf"

    email_sender=""
    email_sender_pass=""
    email_receiver=""
    email_relay="smtp.gmail.com"
    email_relay_port="587"

    aws_s3_key=""
    aws_s3_secret=""
    aws_s3_bucket=""
    aws_s3_bucket_dir=""
    aws_s3_region="eu-central-1"
    ```
3. Execute a database backup:
```
bash /<<cloned_repository_path>>/mysql_backup/backup.sh
```
4. Execute a database restore test:
```
bash /<<cloned_repository_path>>/mysql_backup/restore.sh --dry-run
```
5. **(OPTIONAL)(DO NOT PROCEED UNTESTED(step 4)!)** Execute a production database restore:
```
bash /<<cloned_repository_path>>/mysql_backup/restore.sh
```

## What this backup method is good for
1. Doing backup and restore for non-Enterprise MySQL server version
2. If the MySQL server is a single instance and it's not intended to be used for MySQL cluster backup (though, it can be used as a part of restore/backup on Slave)
3. Great solution for small projects without intensive writes

## The downsides of this backup method
1. It can't backup and restore incrementally
2. It's not recommended to use it for MySQL cluster due to locks
3. It's not recommended to use it for write intensive databases due to locks

## When the database keeps growing...
1. Grow hardware vertically (more RAM, faster CPUs and disks) and increase buffers
2. Switch to MySQL Enterprise or MariaDB or Percona Server to have incremental backups (or Postgres, sorry)
3. Do Master-Slave clustering
4. Try combining different DB engines for different parts of application(s)
4. If everything gets reeealy big: try sharding or switching to heterogenous database solutions
