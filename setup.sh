#!/bin/bash

DEFAULT_USER=root
BUCKET_NAME=homebucket
SECRETS_FILE=.secrets.env
URL_SENSE_AUTHENTICATE="https://api.sense.com/apiservice/api/v1/authenticate"

if [[ -f "$SECRETS_FILE" ]]; then
    echo "will not set up when $SECRETS_FILE exists -- we're already setup. Just docker compose up"
    exit 1
fi

touch "$SECRETS_FILE"

run () {
    tmp=$(mktemp)
    $@ &> "$tmp"
    if (( $? )) ; then
        echo -e "ERROR RUNNING $@\n----"
        cat "$tmp"
        echo '----'
    fi
    rm "$tmp"
}

echo "Building images..."
run docker compose build

echo "Setting up sense..."
echo -n "Sense email: "
read SENSE_USERNAME
echo -n "Sense password: "
read -s SENSE_PASSWORD
response_url_sense=$(curl --silent --show-error --fail -k --data "email=${SENSE_USERNAME}" --data "password=${SENSE_PASSWORD}" -H "Sense-Collector-Client-Version: 1.0.0" -H "X-Sense-Protocol: 3" -H "User-Agent: okhttp/3.8.0" "${URL_SENSE_AUTHENTICATE}")

SENSE_TOKEN=$(echo "${response_url_sense}" | jq -r .access_token)
SENSE_USER_ID=$(echo "${response_url_sense}" | jq -r .user_id)
SENSE_ID=$(echo "${response_url_sense}" | jq -r .monitors[].id)
SENSE_TZ=$(echo "${response_url_sense}" | jq -r .monitors[].time_zone)
INFLUX_USERNAME=$DEFAULT_USER
#echo -n "Influx Password: "
#read -s INFLUX_PASSWORD
INFLUX_PASSWORD=rootroot

export GF_SECURITY_ADMIN_USER=$DEFAULT_USER
#echo -n "Grafana Password: "
#read -s GF_SECURITY_ADMIN_PASSWORD
export GF_SECURITY_ADMIN_PASSWORD=rootroot

echo "Starting influxdb..."
run docker compose up -d influxdb
sleep 2
echo -n 'Waiting for influxdb...  '
sp="/-\|"
until docker inspect influxdb > /dev/null 2>&1
do
    sleep 1;
    printf "\b${sp:i++%${#sp}:1}"
done;

until [ "`docker inspect -f {{.State.Health.Status}} influxdb`"=="healthy" ]; do
    sleep 1;
    printf "\b${sp:i++%${#sp}:1}"
done;
echo ''

echo "Configuring influxdb"

# setup user and pass
run docker exec influxdb influx setup --skip-verify --bucket $BUCKET_NAME --org home --username $INFLUX_USERNAME --password $INFLUX_PASSWORD --retention 0 --force
# get our auto-gen'd token
INFLUX_TOKEN=$(docker exec influxdb influx config ls --json | jq -r .default.token)
# make sure the config is set to use the token
run docker exec influxdb influx config create --config-name auth-home --host-url http://localhost:8086 --org home --token $INFLUX_TOKEN --active --json > /dev/null
# get the 'default' bucket id
BUCKET_ID=$(docker exec influxdb influx bucket ls --name $BUCKET_NAME --json | jq -r .[].id)
# not sure we need this, but its the token for the telegraf conf
#TELEGRAF_ID=$(docker exec influxdb influx telegrafs --org home create --name telegraf-sense --description "local telegraf for sense.py" -f /etc/telegraf/telegraf.conf --json | jq -r .id)
# token scoped for our telegraf agent
TELEGRAF_TOKEN=$(docker exec influxdb influx auth create --org home --write-bucket $BUCKET_ID --read-telegrafs --json | jq -r .token)

cat <<EOF > .secrets.env
GF_INSTALL_PLUGINS=grafana-clock-panel,digrich-bubblechart-panel
SENSE_TOKEN=$SENSE_TOKEN
SENSE_USER_ID=$SENSE_USER_ID
INFLUX_TOKEN=$INFLUX_TOKEN
TELEGRAF_TOKEN=$TELEGRAF_TOKEN
INFLUX_BUCKET=$BUCKET_NAME
SENSE_ID=$SENSE_ID
SENSE_TZ=$SENSE_TZ
GF_SECURITY_ADMIN_USER=${GF_SECURITY_ADMIN_USER}
GF_SECURITY_ADMIN_PASSWORD=${GF_SECURITY_ADMIN_PASSWORD}
EOF

echo -e "Influx Credentials:\n\t$INFLUX_USERNAME\n\t$INFLUX_PASSWORD"
echo -e "Influx Token:\n\t$INFLUX_TOKEN"
echo -e "Telegraf Token:\n\t$TELEGRAF_TOKEN"
echo -e "Influx bucket: $BUCKET_ID"
echo -e "Grafana Credentials:\n\t$GF_SECURITY_ADMIN_USER\n\t$GF_SECURITY_ADMIN_PASSWORD"

run docker compose down
docker compose up -d
