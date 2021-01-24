#!/usr/bin/env bash


backup_tmp_dir="/tmp"
get_date="$(date +%F-%H_%M_%S)"

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

function mysql_config {
cat > $mysql_connect_conf << EOF
[client]
user = "$mysql_user"
password = "$mysql_password"
host = "$mysql_host"
port = "$mysql_port"
socket = "$mysql_socket"
[mysqldump]
user = "$mysql_user"
password = "$mysql_password"
host = "$mysql_host"
port = "$mysql_port"
socket = "$mysql_socket"
max-allowed-packet = 16G
quick
EOF
}

function mysql_connect {
  mysql_config
  $mysql_bin --defaults-extra-file=$mysql_connect_conf "$@"
  [[ "${PIPESTATUS[0]}" != "0" ]] && return 1
}

function mysql_dump {
  mysql_config
  $mysql_dump_bin --defaults-extra-file=$mysql_connect_conf "$@"
  [[ "${PIPESTATUS[0]}" != "0" ]] && return 1
}

function cleanup {
  rm -f $mysql_connect_conf
}
