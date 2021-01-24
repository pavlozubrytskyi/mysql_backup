#!/usr/bin/env bash

source ./.config.sh

log_file="${backup_tmp_dir}/${mysql_db_name}.${get_date}.restore.log"
db_archive=${backup_tmp_dir}/${mysql_db_name}.latest.tar.gz

download_backup () {

  echo "$(date +%F-%H:%M:%S) Restore started"

  aws_service_endpoint_url="s3.${aws_s3_region}.amazonaws.com"
  aws_s3_path="$(echo /${aws_s3_bucket_dir}${mysql_db_name}.latest.tar.gz | sed 's;^\([^/]\);/\1;')"


  hash_sha256 () {
    printf "${1}" | openssl dgst -sha256 | sed 's/^.* //'
  }

  hmac_sha256 () {
    printf "${2}" | openssl dgst -sha256 -mac HMAC -macopt "${1}" | sed 's/^.* //'
  }

  current_date_day="$(date -u '+%Y%m%d')"
  current_date_iso8601="${current_date_day}T$(date -u '+%H%M%S')Z"

  http_request_payload_hash="$(printf "" | openssl dgst -sha256 | sed 's/^.* //')"
  http_canonical_request_uri="/${aws_s3_bucket}${aws_s3_path}"
  http_request_content_type='application/octet-stream'

http_canonical_request_headers="content-type:${http_request_content_type}
host:${aws_service_endpoint_url}
x-amz-content-sha256:${http_request_payload_hash}
x-amz-date:${current_date_iso8601}"
# Note: The signed headers must match the canonical request headers.
http_request_signed_headers="content-type;host;x-amz-content-sha256;x-amz-date"
http_canonical_request="GET
${http_canonical_request_uri}\n
${http_canonical_request_headers}\n
${http_request_signed_headers}
${http_request_payload_hash}"

  create_signature () {
    stringtosign="AWS4-HMAC-SHA256\n${current_date_iso8601}\n${current_date_day}/${aws_s3_region}/s3/aws4_request\n$(hash_sha256 "${http_canonical_request}")"
    datekey=$(hmac_sha256 key:"AWS4${aws_s3_secret}" "${current_date_day}")
    regionkey=$(hmac_sha256 hexkey:"${datekey}" "${aws_s3_region}")
    servicekey=$(hmac_sha256 hexkey:"${regionkey}" "s3")
    signingkey=$(hmac_sha256 hexkey:"${servicekey}" "aws4_request")

    printf "${stringtosign}" | openssl dgst -sha256 -mac HMAC -macopt hexkey:"${signingkey}" | sed 's/(stdin)= //'
  }

  signature="$(create_signature)"
  http_request_authorization_header="\
  AWS4-HMAC-SHA256 Credential=${aws_s3_key}/${current_date_day}/\
  ${aws_s3_region}/s3/aws4_request, \
  SignedHeaders=${http_request_signed_headers}, Signature=${signature}"


  echo "Downloading https://${aws_service_endpoint_url}${http_canonical_request_uri} to $db_archive"

curl "https://${aws_service_endpoint_url}${http_canonical_request_uri}" \
    -H "Authorization: ${http_request_authorization_header}" \
    -H "content-type: ${http_request_content_type}" \
    -H "x-amz-content-sha256: ${http_request_payload_hash}" \
    -H "x-amz-date: ${current_date_iso8601}" \
    -f --progress-bar --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -o ${db_archive}

[[ "${PIPESTATUS[0]}" != "0" ]] && echo "Something went wrong with backup download!!!" && return 1

  return 0

}

restore_backup () {

  unpack_dir="${backup_tmp_dir}/${mysql_db_name}.restore.${get_date}"

  mkdir -p ${unpack_dir} && tar -xzvf ${db_archive} -C ${unpack_dir}
  [[ "${PIPESTATUS[0]}" != "0" ]] && echo "Something went wrong with backup unpacking!!!" && return 1

  get_tables="$(ls ${unpack_dir}/*/*.sql)"

  for table_chsm in ${get_tables}; do
    sha256sum ${table_chsm} >> ${unpack_dir}/checksums_restore_tmp
  done

  sha256sum ${unpack_dir}/*/${mysql_db_name}.database.table.schema >> ${unpack_dir}/checksums_restore_tmp

  cat ${unpack_dir}/checksums_restore_tmp | cut -d'/' -f1,5|sed -e 's/\///g' |sort >> ${unpack_dir}/checksums_restore
  rm ${unpack_dir}/checksums_restore_tmp

  diff ${unpack_dir}/checksums_restore ${unpack_dir}/*/checksums
  [[ "${PIPESTATUS[0]}" != "0" ]] && echo "Checksums don't match, inconsistent database backup, please find another one!!!" && return 1

  #Testing db restore
  if [[ "$1" -eq "--dry-run" ]]; then
    test_db_name="${mysql_db_name}_testing"
    mysql_connect -Bse "create database if not exists ${test_db_name};grant all on ${test_db_name}.* to '${mysql_user}'@'localhost' identified by '${mysql_password}';flush privileges;"
    [[ "${PIPESTATUS[0]}" != "0" ]] && echo "Something went wrong with test db creation!!!" && return 1

    echo "mysql_connect ${test_db_name} < ${unpack_dir}/*/${mysql_db_name}.database.table.schema"
    mysql_connect ${test_db_name} < ${unpack_dir}/*/${mysql_db_name}.database.table.schema
    [[ "${PIPESTATUS[0]}" != "0" ]] && echo "Couldn't restore ${test_db_name} schema backup, restore test failed!!!" && return 1

    for table in ${get_tables}; do
       echo "mysql_connect ${test_db_name} < ${table}"
       mysql_connect ${test_db_name} < ${table}
       [[ "${PIPESTATUS[0]}" != "0" ]] && echo "Couldn't restore ${test_db_name} ${table} backup, restore test failed!!!" && return 1
    done

    mysql_connect -Bse "drop database ${test_db_name}"
  fi

  #Production db restore
  if [[ "$1" -ne "--dry-run" ]]; then
    mysql_connect -Bse "create database if not exists ${mysql_db_name};grant all on ${mysql_db_name}.* to '${mysql_user}'@'localhost' identified by '${mysql_password}';flush privileges;"
    [[ "${PIPESTATUS[0]}" != "0" ]] && echo "Something went wrong with test db creation!!!" && return 1

    echo "mysql_connect ${mysql_db_name} < ${unpack_dir}/*/${mysql_db_name}.database.table.schema"
    mysql_connect ${mysql_db_name} < ${unpack_dir}/*/${mysql_db_name}.database.table.schema
    [[ "${PIPESTATUS[0]}" != "0" ]] && echo "Couldn't restore ${mysql_db_name} schema backup, restore failed!!!" && return 1

    for table in ${get_tables}; do
       echo "mysql_connect ${mysql_db_name} < ${table}"
       mysql_connect ${mysql_db_name} < ${table}
       [[ "${PIPESTATUS[0]}" != "0" ]] && echo "Couldn't restore ${mysql_db_name} ${table} backup, restore failed!!!" && return 1
    done
  fi

  rm -rf ${unpack_dir}

  echo "$(date +%F-%H:%M:%S) Restore completed"

  return 0
}

[[ -f "${db_archive}" ]] || download_backup 2>&1 | tee ${log_file}
download_status="${PIPESTATUS[0]}"

if [[ "${download_status}" -ne "0" ]]; then
  echo "Sending to ${email_receiver}"
  send_report restore
  cleanup
else
  restore_backup $1 2>&1 | tee ${log_file}
  send_status="${PIPESTATUS[0]}"
  if [[ "${send_status}" -ne "0" ]]; then
    echo "Sending to ${email_receiver}"
    send_report restore
    cleanup
  else
    echo "MySQL download and restore has been completed"
    rm ${log_file}
    cleanup
  fi

fi
