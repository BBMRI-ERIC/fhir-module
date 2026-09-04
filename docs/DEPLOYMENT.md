# Deployment

The recommended production deployment is to run the application as a Docker container on a Linux VM that most likely 
already has a Blaze FHIR server running in Docker. In that setup it is recommended to connect the application to the 
same Docker network(s) as the existing Blaze container(s).

## Prerequisites:

List of prerequisites for running the application on one of the supported operating systems:
- Linux Ubuntu 22.04 
- [Docker engine v24.0.0](https://docs.docker.com/engine/release-notes/24.0/#2400)
- [Docker compose v2.20](https://docs.docker.com/compose/release-notes/#2200)

## Minimal Docker deployment
For deploying to production, configure the application using environment variables in the `compose.yaml` file, 
create the necessary configuration files (see documentation below) and mount the directory containing patient 
records/data.


> [!NOTE]
> Depending on your system configuration, you may need to use sudo when running Docker commands.
> If your user is part of the docker group, you can run Docker commands directly (e.g., docker run, docker compose up) without elevated privileges.


### Step 1: Find the Blaze Docker networks
First, identify the running Blaze containers on your server (for example **bridgehead-bbmri-blaze**):
```shell
docker ps
```
Inspect the Blaze container to find the network it is connected to (for example **bbmri-default**):
```shell
docker inspect <container> --format 'Container: {{.Name}}{{"\n"}}{{range $net, $cfg := .NetworkSettings.Networks}}  └─ Network: {{$net}} {{"\n"}}{{end}}'
```
---

### Step 2: Create the deployment directory
```shell
sudo mkdir -p /opt/fhir-module
cd /opt/fhir-module
```
Inside this directory, you need to create the util directory for configuration files.
```shell
sudo mkdir -p util
cd util
```
In this directory, create the `default_sample_collection.json` file. This file defines the sample collections that will  
be uploaded into Blaze. Uploaded samples are linked to these collections during synchronization. So identifiers in this 
file should match the collection identifiers produced by the application’s mapping configuration.
An example of the file can be found here [default_sample_collection.json](../util/default_sample_collection.json).
<br>

Next, create the `default_biobank.json` file. This file defines the biobank that will be uploaded into Blaze. 
It is especially important when MIABIS on FHIR is enabled, because in that model the biobank acts as the parent 
resource for the collections.
An example of the file can be found here [default_biobank.json](../util/default_biobank.json).

Once the files are prepared, return to the main directory:
```shell
cd ..
```
At this point, the directory should look like this:
```text
/opt/fhir-module
└── util/
    ├── default_biobank.json
    └── default_sample_collection.json
```

---

### Step 3: Create Compose configuration
Create the `compose.yaml` file with the following content and replace the placeholder values with the real values from your
environment:

In the `environment` section below, `DIR_PATH`, `SAMPLE_COLLECTIONS_PATH`, and `BIOBANK_PATH` are paths inside the container.
They must match the corresponding bind mount `target` paths.

**Important**: Make sure to set the `NEXTAUTH_SECRET` environment variable to a secure random string in production environments.
Generate a NextAuth secret for example with: 
```shell
openssl rand -base64 32
```

```yaml
services:
  fhir-module:
    image: ghcr.io/bbmri-eric/fhir-module:latest
    container_name: fhir-module
    profiles:
      - prod
    restart: unless-stopped
    ports:
      - "5000:5000" # FHIR module port
      - "3000:3000" # UI port
    environment:
      BLAZE_URL: "http://blaze:8080/fhir" # replace with container name and port of Blaze
      MIABIS_ON_FHIR: "False"
      DIR_PATH: "/opt/records" # container path for mounted records; must match volume target
      SAMPLE_COLLECTIONS_PATH: "/opt/fhir-module/util/default_sample_collection.json" # container path; must match volume target
      BIOBANK_PATH: "/opt/fhir-module/util/default_biobank.json" # container path; must match volume target
      PYTHONWARNINGS: "ignore:Unverified HTTPS request"
      NEXTAUTH_SECRET: "GENERATED_KEY"  # Fill your generated random string
      AUTH_TRUST_HOST: true
      NODE_ENV: "production"
    command:
      [
        "/bin/sh",
        "-c",
        "chmod 666 /opt/fhir-module/util/shared_config.json && /usr/local/bin/startup.sh",
      ]
    volumes:
      - type: bind
        source: "./records" # host path with your data
        target: "/opt/records"
      - type: bind
        source: "./util/default_sample_collection.json" # host path to sample collections file
        target: "/opt/fhir-module/util/default_sample_collection.json"
        read_only: true
      - type: bind
        source: "./util/default_biobank.json" # host path to biobank file
        target: "/opt/fhir-module/util/default_biobank.json"
        read_only: true
      - fhir-logs:/var/log/fhir-module
      - ui-data:/app/data
      - config-snapshots:/opt/config-snapshots
    networks:
      - main-blaze-network
    healthcheck:
      test:
        [
          "CMD",
          "sh",
          "-c",
          "curl -f http://localhost:3000 && curl -f http://localhost:8080/metrics",
        ]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  
networks:
  main-blaze-network:
    external: true
    name: bbmri_default # replace with the network of your Blaze container
volumes:
  fhir-logs:
  ui-data:
  config-snapshots:
```

---
### Step 4: Start the application

```shell
docker compose --profile prod up -d
```
To verify that the container is running, use the command:
```shell
docker ps
```
And check the logs to see if the application started correctly:
```shell
docker logs fhir-module -f
```

if connection to Blaze was successful, you should see the following line:
` Starting sync with Blaze 🔥!`

Access the UI at **http://localhost:3000** (or replace localhost with your server IP if not running locally). 
Default login: `admin` / `Admin123!` (change immediately!)


## Advanced Docker Deployment

### Environment variables

The FHIR module is configured via environment variables, all of which can be found below.

| Variable name                 | Required                                   | Default value                                          | Description                                                                                                                                                                        |
| ----------------------------- | ------------------------------------------ | ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| BLAZE_URL                     | true                                       | http://localhost:8080/fhir                             | Base url of the FHIR server for sync. No trailing slash. When deployed in container, localhost is replaced by the blaze container name.                                            |
| MIABIS_BLAZE_URL              | false (true if MIABIS_ON_FHIR)             | http://localhost:5432/fhir                             | Base url of the FHIR server for syncing specifically the MIABIS on FHIR profile. No trailing slash. When deployed in container, localhost is replaced by the blaze container name. |
| MIABIS_ON_FHIR                | false                                      | False                                                  | Flag allowing users to start the FHIR-module with/without newest MIABIS on FHIR profile.(pilot implementation of the new profile, False for production)                            |
| BLAZE_USER                    | false                                      | _empty_                                                | Basic auth username for accessing the blaze store via HTTP.                                                                                                                        |
| BLAZE_PASS                    | false                                      | _empty_                                                | Basic auth password for accessing the blaze store via HTTP.                                                                                                                        |
| NEW_FILE_PERIOD_DAYS          | false                                      | 30                                                     | Specifies the number of days for the next upload of record file(s).                                                                                                                |
| SMTP_HOST                     | false                                      | localhost                                              | Specifies hostname or IP address of the SMTP server used for sending notification mails about freshness of records.                                                                |
| SMTP_PORT                     | false                                      | 1025                                                   | Port number sued to connect to the SMTP server for sending notification mails about fresshnes of records.                                                                          |
| EMAIL_RECEIVER                | false                                      | test@example.com                                       | Mail address that the notification emails will be send to.                                                                                                                         |
| LOG_LEVEL                     | false                                      | INFO                                                   | minimum severity of logs to be recorded. values are : INFO, DEBUG,ERROR                                                                                                            |
| PARSING_MAP_PATH              | false (can be set by the UI)               | /opt/fhir-module/default_map.json                      | Path to a JSON file containing object parsing mappings. Example [here](../util/default_map.json).                                                                                  |
| MATERIAL_TYPE_MAP_PATH        | false (can be set by the UI)               | /opt/fhir-module/default_material_type_map.json        | Path to a JSON file containing mappings between organizational and FHIR material types. Example [here](../util/default_material_type_map.json).                                    |
| MIABIS_MATERIAL_TYPE_MAP_PATH | false (can be set by the UI)               | /opt/fhir-module/default_miabis_material_type_map.json | Path to a JSON file containing mappings between organizational and MIABIS on FHIR material types. Example [here](../util/default_miabis_material_type_map.json)                    |
| SAMPLE_COLLECTIONS_PATH       | false (can be set by the UI)               | /opt/fhir-module/default_sample_collection.json        | Path to a JSON file containing information about Sample collections. Example [here](../util/default_sample_collection.json).                                                       |
| BIOBANK_PATH                  | true                                       | /opt/fhir-module/default_biobank.json                  | Path to a JSON file containing information about Biobank. Example [here](..util/default_biobank.json)                                                                              |
| STORAGE_TEMP_MAP_PATH         | false (can be set by the UI)                                     | /opt/fhir-module/default_storage_temp_map.json         | Path to a JSON file containing mapping between organizational and FHIR storage temperature. Example [here](../util/default_storage_temp_map.json).                                 |
| MIABIS_STORAGE_TEMP_MAP_PATH  | false (can be set by the UI)                                    | /opt/fhir-module/default_miabis_storage_temp_map.json  | Path to a JSON file containing mapping between organizational and MIABIS on FHIR storage temperature. Example [here](../util/default_miabis_storage_temp_map.json)                 |
| TYPE_TO_COLLECTION_MAP_PATH   | false (can be set by the UI)                                     | /opt/fhir-module/default_type_to_collection_map.json   | Path to a JSON file containig mapping of attribute (provided in the PARSING_MAP) to a collection. Example [here](../util/default_type_to_collection_map.json).                     |                                                                                              |
| RECORDS_DIR_PATH              | false (can be set by the UI)               | /mock_dir/                                             | Path to a folder containing file(s) with records.                                                                                                                                  |
| RECORDS_FILE_TYPE             | false (can be set by the UI)               | xml                                                    | Type of files containing the records.                                                                                                                                              |
| CSV_SEPARATOR                 | false (can be set by the UI, true for csv) | ;                                                      | Separator used inside csv file, if the records are in a csv format.                                                                                                                |

#### UI Application Variables

The following environment variables are used to configure the Next.js UI application:

| Variable name                  | Default value                     | Description                                                                  |
|--------------------------------| --------------------------------- |------------------------------------------------------------------------------|
| NODE_ENV                       | development                       | Node.js environment mode (development/production)                            |
| PORT                           | 3000                              | Port on which the UI application runs                                        |
| NEXTAUTH_SECRET                | _required_                        | Secret key for NextAuth.js session encryption. **Must be set in production** |
| AUTH_TRUST_HOST                | false                             | Set to `true` for Docker deployment to trust proxy headers                   |
| BACKEND_API_URL                | http://localhost:5000             | URL of the FHIR module backend API                                           |
| PROMETHEUS_URL                 | http://prometheus:9090            | URL of the Prometheus metrics server                                         |
| PASSWORD_MIN_LENGTH            | 8                                 | Minimum password length requirement                                          |
| PASSWORD_MAX_LENGTH            | 128                               | Maximum password length requirement                                          |
| PASSWORD_REQUIRE_UPPERCASE     | false                             | Require uppercase letters in passwords                                       |
| PASSWORD_REQUIRE_LOWERCASE     | false                             | Require lowercase letters in passwords                                       |
| PASSWORD_REQUIRE_NUMBERS       | false                             | Require numbers in passwords                                                 |
| PASSWORD_REQUIRE_SPECIAL_CHARS | false                             | Require special characters in passwords                                      |
| PASSWORD_SPECIAL_CHARS         | !@#$%^&\*()\_+-=[]{}&#124;;:,.<>? | Allowed special characters for passwords                                     |
| HTTPS_PROXY                    | _empty_                           | Proxy URL for outbound HTTPS requests (e.g. `https://proxy:3128`)            |
| HTTP_PROXY                     | _empty_                           | Proxy URL for outbound HTTP requests (e.g. `http://proxy:3128`)              |
| NO_PROXY                       | _empty_                           | Comma-separated list of domains for which to bypass proxy                    |

## Object mapping

The FHIR module uses dynamically configurable maps currently stored as json files
to parse XML,CSV or JSON into Python objects.

See [MAPS.md](MAPS.md) for detailed documentation on configuring object mappings.

---

## Complete Deployment Guide

This guide allows you to deploy the FHIR module from scratch. You only need Docker installed - all files can be created by copying from this documentation.

---
#### First-time Setup

On first deployment, the UI will automatically:

1. Initialize the SQLite database
2. Create default user accounts
3. Set up authentication system

### Step 1: Create a Folder and the `compose.yaml`

Create a new folder anywhere on your server and save this as `compose.yaml`:

```shell
mkdir fhir-deployment && cd fhir-deployment
```

Create `compose.yaml` with this content:

```yaml
services:
  fhir-module:
    image: ghcr.io/bbmri-eric/fhir-module:latest
    container_name: fhir-module
    profiles:
      - dev
      - prod
    networks:
      - fhir-integration
      - monitoring
    restart: unless-stopped
    ports:
      - "5000:5000" # FHIR module port
      - "3000:3000" # UI port
      - "9100:8080" # Prometheus metrics port
    environment:
      BLAZE_URL: "${BLAZE_URL:-http://test-blaze:8080/fhir}"
      MIABIS_BLAZE_URL: "${MIABIS_BLAZE_URL:-http://miabis-blaze:8080/fhir}"
      MIABIS_ON_FHIR: "${MIABIS_ON_FHIR:-True}"
      DIR_PATH: "/opt/records"
      SAMPLE_COLLECTIONS_PATH: "/opt/fhir-module/util/default_sample_collection.json"
      BIOBANK_PATH: "/opt/fhir-module/util/default_biobank.json"
      PYTHONWARNINGS: "ignore:Unverified HTTPS request"
      NEXTAUTH_SECRET: "YOUR_KEY"  # Fill your generated key
      AUTH_TRUST_HOST: true
      NODE_ENV: "production"
      PROMETHEUS_URL: "http://prometheus:9090"
    command:
      [
        "/bin/sh",
        "-c",
        "chmod 666 /opt/fhir-module/util/shared_config.json && /usr/local/bin/startup.sh",
      ]
    volumes:
      - type: bind
        source: "test/xml_data" # location of your data
        target: "/opt/records" 
      - type: bind
        source: "./util/default_sample_collection.json" # location of your collection definition
        target: "/opt/fhir-module/util/default_sample_collection.json"
      - type: bind
        source: "./util/default_biobank.json" # location of your biobank definition
        target: "/opt/fhir-module/util/default_biobank.json"
      - fhir-logs:/var/log/fhir-module
      - ui-data:/app/data
      - config-snapshots:/opt/config-snapshots
    healthcheck:
      test:
        [
          "CMD",
          "sh",
          "-c",
          "curl -f http://localhost:3000 && curl -f http://localhost:8080/metrics",
        ]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  prometheus:
    image: prom/prometheus:latest
    profiles:
      - monitoring
    networks:
      - monitoring
    ports:
      - "9090:9090"
    volumes:
      - type: bind
        source: "./config/prometheus.yml"  # path to your config file
        target: "/etc/prometheus/prometheus.yml"
      - prometheus_data:/prometheus
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--web.console.libraries=/usr/share/prometheus/console_libraries"
      - "--web.console.templates=/usr/share/prometheus/consoles"

  miabis-blaze:
    container_name: miabis-blaze
    image: "samply/blaze:latest"
    networks:
      - fhir-integration
      - monitoring
    profiles:
      - dev
      - prod
    environment:
      JAVA_TOOL_OPTIONS: "-Xmx2g"
      DB_SEARCH_PARAM_BUNDLE: "/app/searchParamBundle.json"
      LOG_LEVEL: "debug"
    ports:
      - "5432:8080"
    volumes:
      - type: bind
        source: "util/searchParamBundle.json"
        target: "/app/searchParamBundle.json"

  test-blaze:
    container_name: test-blaze
    image: "samply/blaze:latest"
    networks:
      - fhir-integration
      - monitoring
    profiles:
      - dev
    environment:
      JAVA_TOOL_OPTIONS: "-Xmx2g"
      DB_SEARCH_PARAM_BUNDLE: "/app/searchParamBundle.json"
      LOG_LEVEL: "debug"
    ports:
      - "8080:8080"
    volumes:
      - type: bind
        source: "util/searchParamBundle.json"
        target: "/app/searchParamBundle.json"

  promtail:
    image: grafana/promtail:latest
    container_name: promtail
    profiles:
      - monitoring
    networks:
      - monitoring
    volumes:
      - fhir-logs:/var/log/fhir-module:ro
      - type: bind
        source: "./config/promtail-config.yaml" # path to your config file
        target: "/etc/promtail/promtail-config.yaml"
    command: -config.file=/etc/promtail/promtail-config.yaml

networks:
  fhir-integration:
  monitoring:

volumes:
  prometheus_data:
  fhir-logs:
  ui-data:
  config-snapshots:
```

The profile flags below refer to the `compose.yaml` created in Step 1.

```shell
--profile prod
--profile dev
--profile monitoring
```

A complete example is:

```shell
docker compose --profile dev --profile monitoring up -d
```
---

### Step 2: Start the Application

```shell
# Pull images and start
docker compose --profile prod up -d
```

Access the UI at **http://localhost:3000**

Default login: `admin` / `Admin123!` (change immediately!)

---

### (Optional) Step 3: Add Monitoring

If you want metrics and log collection to Grafana Cloud, create these additional files:

**Create `config/prometheus.yml`:**

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    environment: "${ENVIRONMENT}" # name of your environment

scrape_configs:
  - job_name: "fhir-module"
    static_configs:
      - targets: ["fhir-module:8080"]
    metrics_path: "/metrics"

remote_write:
  - url: "${PROM_REMOTE_URL}"
    basic_auth:
      username: "${PROM_REMOTE_USER}" # datasource configured in grafana
      password: "${PROM_REMOTE_PASS}" # datasource configured in grafana
```

**Create `config/promtail-config.yaml`:**

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /etc/promtail/positions.yaml

clients:
  - url: "${GRAFANA_LOGS_URL}"
    basic_auth:
      username: "${GRAFANA_LOGS_USERNAME}" # datasource configured in grafana
      password: "${GRAFANA_LOGS_PASSWORD}"

scrape_configs:
  - job_name: fhir-module-sync # If not miabis, else delete
    static_configs:
      - targets: ["localhost"]
        labels:
          job: blaze
          environment: "${ENVIRONMENT}" # name of your environment
          __path__: /var/log/fhir-module/sync.log
    pipeline_stages:
      - json:
          expressions:
            timestamp: timestamp
            level: level
            sync_summary: sync_summary
      - timestamp:
          source: timestamp
          format: "2006-01-02 15:04:05,000"
      - labels:
          level:

  - job_name: fhir-module-miabis-sync # If miabis, else delete
    static_configs:
      - targets: ["localhost"]
        labels:
          job: miabis-blaze
          environment: "${ENVIRONMENT}" # name of your environment
          __path__: /var/log/fhir-module/miabis_sync.log
    pipeline_stages:
      - json:
          expressions:
            timestamp: timestamp
            level: level
            sync_summary: sync_summary
      - timestamp:
          source: timestamp
          format: "2006-01-02 15:04:05,000"
      - labels:
          level:

```

**Start with monitoring:**

```shell
docker compose --profile prod --profile monitoring up -d
```

---

### Quick Commands

```shell
# Start
docker compose --profile prod up -d

# Start with monitoring
docker compose --profile prod --profile monitoring up -d

# Stop
docker compose --profile prod down

# Restart
docker compose --profile prod restart
```
