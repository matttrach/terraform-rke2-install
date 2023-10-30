#!/bin/sh
set -x
set -e
ROLE="${1}"
SERVICE_NAME="rke2-${ROLE}.service"
if [ "$(systemctl is-active "${SERVICE_NAME}")" = "active" ]; then
 systemctl stop "${SERVICE_NAME}"
fi
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl start "${SERVICE_NAME}" &

EXIT=0
max_attempts=20
attempts=0
interval=10
while [ "$(systemctl is-active "${SERVICE_NAME}")" != "active" ]; do
  echo "${SERVICE_NAME} status is \"$(systemctl is-active "${SERVICE_NAME}")\""
  attempts=$((attempts + 1))
  if [ ${attempts} = ${max_attempts} ]; then EXIT=1; break; fi
  sleep ${interval};
done
echo "${SERVICE_NAME} status is \"$(systemctl is-active "${SERVICE_NAME}")\""

exit $EXIT