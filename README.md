# FHIR module

[![CI build](https://github.com/BBMRI-ERIC/fhir-module/actions/workflows/build.yml/badge.svg)](https://github.com/BBMRI-ERIC/fhir-module/actions/workflows/build.yml) [![codecov](https://codecov.io/gh/BBMRI-ERIC/fhir-module/branch/main/graph/badge.svg?token=3eklJNhIS5)](https://codecov.io/gh/BBMRI-ERIC/fhir-module) [![Python 3.11](https://img.shields.io/badge/python-3.11-blue.svg)](https://www.python.org/downloads/release/python-360/) [![Linter: pylint](https://img.shields.io/badge/Linter-pylint-yellowgreen)](https://github.com/pylint-dev/pylint)

The [BBMRI-ERIC](https://www.bbmri-eric.eu/) FHIR module is a container based application connecting biobanks
to other IT tools and services in our ecosystem on a local level.

## Goal

The goal of this project is to create a highly customizable data integration tool for biobanks that are a
part of BBMRI-ERIC. This tool should support ETL processes by providing the following functionality:

- Data harmonization to [HL7 FHIR](https://www.hl7.org/fhir/)
  - HARMONIZATION for [BBMRI.de](https://simplifier.net/bbmri.de) profile - currently used by BBMRI-ERIC Locator
  - HARMONIZATION for [MIABIS on FHIR](https://simplifier.net/miabis) profile - FHIR profile representing latest MIABIS version (MIABIS Core 3.0 + Individual-level sample components)
- Data quality validation - validates the provided files and mappings - see [Deployment](docs/DEPLOYMENT.md)
- Reporting and monitoring (coming soon)

## Glossary

- [Deployment Guide](/docs/DEPLOYMENT.md)
- [User Interface (UI)](/docs/UI.md)
- [Data Model](/docs/DATA_MODEL.md)
- [Security](/docs/SECURITY.md)
- [Monitoring](/docs/MONITORING.md)
- [Maps Documentation](/docs/MAPS.md)
- [Contributing](/docs/CONTRIBUTING.md)

## State

Supports syncing of patients and their samples between a [Blaze FHIR store](https://github.com/samply/blaze) and a repository of XML,CSV or JSON files
stored on a regular filesystem.

This application supports transformation from 3 file types. XML,CSV, and JSON.

This application Transforms data into the two FHIR profiles, BBMRI.de and MIABIS on FHIR, as mentioned above.
Each representation is stored in an independent Blaze FHIR store. MIABIS on FHIR representation serves as a pilot use-case of the newly created profile.

Currently, the XML files must have the same structure as this [test file](./test/xml_data/MMCI_1.xml).
This module cannot work with different types of files at the same time, so all the records needs to be in either XML,CSV or JSON.

### Contents of provided record file(s)

In order to successfully transform data about patients and samples, the users need to provide this data:

- patient_data:
  - (pseudo)-anonymized ID of a donor
  - donor_birthdate
  - gender
- sample_data:
  - (pseudo)-anonymized ID of the sample
  - material type
  - - diagnosis_datetime - date that the diagnosis was first observed (optional but recommended for better findability in Locator)
  - storage temperature - (optional but recommended for better findability in Locator)
  - ICD10 diagnosis code
  - collection ID which specifies to which collection this sample belongs to (this ID comes from [BBMRI-ERIC Directory](https://directory.bbmri-eric.eu/ERIC/directory/#/catalogue))

**IMPORTANT**: Collection ID does not need to be a new attribute. It can also be already present attribute from which the collection ID can be derived. For more information see [MAPS](docs/MAPS.md)

**DISCLAIMER**: Samples without specified Collection to which they belong to will not be correctly visible in the BBMRI-ERIC Locator

## Quick Start

### Docker

Prerequisites:

- [Docker engine v24.0.0](https://docs.docker.com/engine/release-notes/24.0/#2400)
- [Docker compose v2.20](https://docs.docker.com/compose/release-notes/#2200)

To spin up an instance of the FHIR module along with [Blaze](https://github.com/samply/blaze), clone the repository and
run the following command:

```shell
docker compose --profile dev up -d
```

For a simpler deployment with fewer containers (combined UI + API):

```shell
docker compose --profile combined up -d
```

For additional information about deployment, refer to the [Deployment documentation](docs/DEPLOYMENT.md).

### Workflow

At the start, the FHIR module syncs the provided records - Transforms the provided records into BBMRI.de representation ( and into MIABIS on FHIR representation, if the MIABIS_On_FHIR enviromental variable is set to True - see [Deployment documentation](docs/DEPLOYMENT.md) ) and uploads them to the Blaze FHIR store respectively.

The FHIR module periodically - every week - syncs the Blaze store with the records currently present. Only new patients/samples are uploaded. FHIR module checks if patient/sample is present based on its respctive ID, so please, keep the IDs unique!

### Manual upload

Additionally, after initial upload, users can manually start the sync of BBMRI.de or MIABIS on FHIR profile representation using the commands:

```shell
docker exec fhir-module curl -X POST http://127.0.0.1:5000/sync
```

for syncing the BBMRI.de representation.

```shell
docker exec fhir-module curl -X POST http://127.0.0.1:5000/miabis-sync
```

for syncing the MIABIS on FHIR representation.

### Manual deletion

Users can also delete all of the records currently present in the FHIR store, again either BBMRI.de or MIABIS on FHIR representation using the commands:

```shell
docker exec fhir-module curl -X POST http://127.0.0.1:5000/delete
```

for deleting data representing the BBMRI.de.

```shell
docker exec fhir-module curl -X POST http://127.0.0.1:5000/miabis-delete
```

for deleting data representing the MIABIS on FHIR.

## Contributing

Because the FHIR module is an open source software pull requests are of course welcome! For further information, please
read our [contributing guidelines](docs/CONTRIBUTING.md)!

Found a security vulnerability? Please refer to our [security policy](docs/SECURITY.md).

For instructions on how to set up the development environment, refer to the
[corresponding chapter](docs/CONTRIBUTING.md#development-environment).

## License

Copyright 2023 BBMRI community.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the
License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "
AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific
language governing permissions and limitations under the License.
