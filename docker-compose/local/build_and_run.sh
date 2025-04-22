# run postgres
docker-compose -f ./ops/enterprise/docker-compose/local/postgres/docker-compose.yml up -d --no-deps --build || exit 1 &&

echo "Please wait until postgres finishes to initialize.... (10 seconds)" &&

sleep 10 &&

# run migration scripts
docker-compose -f ./ops/enterprise/docker-compose/local/db-migration/docker-compose.yml up -d --no-deps --build || exit 1 &&

# run keycloak
docker-compose -f ./ops/enterprise/docker-compose/local/keycloak/docker-compose.yml up -d --no-deps --build || exit 1 &&

# run monitoring
#docker-compose -f ./ops/enterprise/docker-compose/local/monitoring/docker-compose.yml up -d --no-deps --build || exit 1 &&

echo "Please wait until keycloak finishes to initialize.... (1-2 minutes)" &&

sleep 90 &&

echo "Keycloak is up.... Running HE" &&

# run HE
docker-compose -f ./ops/enterprise/docker-compose/local/docker-compose.yml up -d --no-deps --build || exit 1 &&

echo "HE is ready to be used on localhost:8080 and keycloak on localhost:8443"
