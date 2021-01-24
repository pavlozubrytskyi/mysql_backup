#!/usr/bin/env bash

source ./.config.sh

log_file="${backup_tmp_dir}/${mysql_db_name}.${get_date}.backup.log"

run_backup () {

  get_tables="$(mysql_connect ${mysql_db_name} -Bse 'show tables;')"

  echo "$(date +%F-%H:%M:%S) Backup started"
  [[ -z "${get_tables}" ]] && echo "Can't connect to database!!!" && return 1
  [[ -d ${backup_tmp_dir}/${mysql_db_name}.${get_date} ]] || mkdir -p ${backup_tmp_dir}/${mysql_db_name}.${get_date}

  for table in $(echo ${get_tables}); do
    echo "$(date +%F-%H:%M:%S) mysql_dump --single-transaction --no-create-info ${mysql_db_name} ${table} > ${backup_tmp_dir}/${mysql_db_name}.${get_date}/${mysql_db_name}.${table}.sql"
    mysql_dump --single-transaction --no-create-info ${mysql_db_name} ${table} > ${backup_tmp_dir}/${mysql_db_name}.${get_date}/${mysql_db_name}.${table}.sql
    [[ "${PIPESTATUS[0]}" != "0" ]] && echo "Something went wrong with mysqldump tables!!!" && return 1
    sha256sum ${backup_tmp_dir}/${mysql_db_name}.${get_date}/${mysql_db_name}.${table}.sql >> ${backup_tmp_dir}/${mysql_db_name}.${get_date}/checksums_tmp
  done;

  echo "$(date +%F-%H:%M:%S) mysql_dump --no-data ${mysql_db_name} > ${backup_tmp_dir}/${mysql_db_name}.${get_date}/${mysql_db_name}.database.table.schema"
  mysql_dump --no-data ${mysql_db_name} > ${backup_tmp_dir}/${mysql_db_name}.${get_date}/${mysql_db_name}.database.table.schema
  [[ "${PIPESTATUS[0]}" != "0" ]] && echo "Something went wrong with mysqldump schema!!!" && return 1
  sha256sum ${backup_tmp_dir}/${mysql_db_name}.${get_date}/${mysql_db_name}.database.table.schema >> ${backup_tmp_dir}/${mysql_db_name}.${get_date}/checksums_tmp

  cat ${backup_tmp_dir}/${mysql_db_name}.${get_date}/checksums_tmp | cut -d'/' -f1,4|sed -e 's/\///g' |sort >> ${backup_tmp_dir}/${mysql_db_name}.${get_date}/checksums
  rm ${backup_tmp_dir}/${mysql_db_name}.${get_date}/checksums_tmp

  echo "$(date +%F-%H:%M:%S) GZIP=-9 tar -cvzf ${backup_tmp_dir}/${mysql_db_name}.${get_date}.tar.gz  -C ${backup_tmp_dir} ${mysql_db_name}.${get_date}"
  GZIP=-9 tar -cvzf ${backup_tmp_dir}/${mysql_db_name}.${get_date}.tar.gz  -C ${backup_tmp_dir} ${mysql_db_name}.${get_date}
  rm -rf ${backup_tmp_dir}/${mysql_db_name}.${get_date}/
  echo "$(date +%F-%H:%M:%S) Backup completed"
  return 0

}

send_backup () {

  aws_ak=${aws_s3_key}
  aws_sk=${aws_s3_secret}
  bucket=${aws_s3_bucket}
  region=${aws_s3_region}
  srcfile="$1"
  targfile=`echo -n "${aws_s3_bucket_dir}" | sed "s/\/$/\/$(basename ${srcfile})/"`
  md5=`openssl md5 -binary "${srcfile}" | openssl base64`

key_and_sig_args=''
if [ "${aws_ak}" != "" ] && [ "${aws_sk}" != "" ]; then
    date=`date -u +%Y%m%dT%H%M%SZ`
    expdate=`if ! date -v+1d +%Y-%m-%d 2>/dev/null; then date -d tomorrow +%Y-%m-%d; fi`
    expdate_s=`printf ${expdate} | sed s/-//g`
    service='s3'
    p=$(cat <<POLICY | openssl base64
{ "expiration": "${expdate}T12:00:00.000Z",
  "conditions": [
    {"acl": "${acl}" },
    {"bucket": "${bucket}" },
    ["starts-with", "\$key", ""],
    ["starts-with", "\$content-type", ""],
    ["content-length-range", 1, `ls -l -H "${srcfile}" | awk '{print $5}' | head -1`],
    {"content-md5": "${md5}" },
    {"x-amz-date": "${date}" },
    {"x-amz-credential": "${aws_ak}/${expdate_s}/${region}/${service}/aws4_request" },
    {"x-amz-algorithm": "AWS4-HMAC-SHA256" }
  ]
}
POLICY
    )
    s=`printf "${expdate_s}"   | openssl sha256 -hmac "AWS4${aws_sk}"           -hex | sed 's/(stdin)= //'`
    s=`printf "${region}"      | openssl sha256 -mac HMAC -macopt hexkey:"${s}" -hex | sed 's/(stdin)= //'`
    s=`printf "${service}"     | openssl sha256 -mac HMAC -macopt hexkey:"${s}" -hex | sed 's/(stdin)= //'`
    s=`printf "aws4_request" | openssl sha256 -mac HMAC -macopt hexkey:"${s}" -hex | sed 's/(stdin)= //'`
    s=`printf "${p}"           | openssl sha256 -mac HMAC -macopt hexkey:"${s}" -hex | sed 's/(stdin)= //'`
    key_and_sig_args="-F X-Amz-Credential=${aws_ak}/${expdate_s}/${region}/${service}/aws4_request -F X-Amz-Algorithm=AWS4-HMAC-SHA256 -F X-Amz-Signature=${s} -F X-Amz-Date=${date}"
fi

  echo "Uploading: ${srcfile} to ${bucket}:${targfile}"
curl                            \
    --connect-timeout 5         \
    --max-time 10               \
    --retry 5                   \
    --retry-delay 0             \
    --retry-max-time 40         \
    --fail                      \
    --progress-bar              \
    -F key=${targfile}          \
    -F acl=${acl}               \
    ${key_and_sig_args}         \
    -F "Policy=${p}"            \
    -F "Content-MD5=${md5}"     \
    -F "Content-Type=${mime}"   \
    -F "file=@${srcfile}"       \
    https://${bucket}.s3-${region}.amazonaws.com/
[[ "${PIPESTATUS[0]}" != "0" ]] && echo "Something went wrong with backup upload!!!" && return 1

  return 0

}

run_backup 2>&1 | tee ${log_file}
backup_status="${PIPESTATUS[0]}"

if [[ "${backup_status}" -ne "0" ]]; then
  echo "Sending to ${email_receiver}"
  send_report backup
  cleanup
else

  mv ${backup_tmp_dir}/${mysql_db_name}.${get_date}.tar.gz ${backup_tmp_dir}/${mysql_db_name}.latest.tar.gz
  send_backup ${backup_tmp_dir}/${mysql_db_name}.latest.tar.gz 2>&1 | tee ${log_file}
  send_status="${PIPESTATUS[0]}"

  if [[ "${send_status}" -ne "0" ]]; then
    echo "Sending to ${email_receiver}"
    send_report backup
    cleanup
  else
    echo "MySQL backup and upload has been completed"
    rm ${log_file}
    cleanup
  fi

fi
