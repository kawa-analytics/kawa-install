# KAWA Installation

This package installs the **KAWA platform** on a single machine — the simple standalone install: **ClickHouse + Postgres**, **no Riyu (AI co-builder)**, AI features completely disabled.

Two installation modes are available in the same package — pick the one that fits your environment:

| | `native` mode | `docker` mode |
|---|---|---|
| How it runs | Directly on the machine, as systemd services | As docker compose services |
| Postgres / ClickHouse | Installed from APT packages | Official docker images |
| KAWA server & workflow engine | Standalone JARs from the KAWA registry | Docker images from the KAWA registry |
| Script runner | `kawapythonserver` python package | Docker image |
| Version format | Exact JAR version (eg. `1.35.1`) | Image tag, branch form (eg. `1.35.x`) |
| Requires | Ubuntu 20.04/22.04/24.04 LTS, root access | Any Linux with docker + docker compose |

**Both modes share the same configuration pieces:**

- `configuration/kawa-registry.credentials` — your access to the KAWA registry (the installer prompts for it)
- `configuration/kawa.config` — the single configuration file: versions, port, features, emails, OIDC, HTTPS…
- `configuration/kawa.secrets` — ALL the secrets: SMTP credentials, OIDC client secret, and the generated keys and JDBC urls
- the **kywy configuration step** — a python client that applies the application configuration through KAWA's commands API (`replace_configuration`), identical in both modes

## How the installation works

Both modes follow the same four steps, handled by `install.sh`:

1. **Download the binaries and configure the environment** — dependencies, databases, secrets (all randomly generated), environment files.
2. **Start everything** — systemd services or docker compose services.
3. **Install kywy and configure KAWA** — applies features, emails, OIDC, the workflow engine and the admin password through the commands API.
4. **Restart** the server to take the configuration into account.

The same cycle applies to any later configuration change:

```bash
sudo vim configuration/kawa.config        # native mode: /etc/kawa/kawa.config
sudo ./install.sh --mode=configure        # re-apply
# restart:
sudo systemctl restart kawa                            # native mode
(cd docker && docker compose restart kawa-server)      # docker mode
```

## 1. Prerequisites

- A **GitLab registry token** (token name + token value), provided by the KAWA support team. It gives access to the docker images (docker mode) and the JARs (native mode). The script runner python package comes from the public PyPI: [kawapythonserver](https://pypi.org/project/kawapythonserver/).
- A valid **KAWA license**.
- Outbound network access to `gitlab.com`, `registry.gitlab.com`, `pypi.org` — or your private python package registry, see section 3.e (and `packages.clickhouse.com` in native mode).
- **native mode**: Ubuntu 20.04, 22.04 or 24.04 LTS (AMD64), an account with sudo, and `git` to clone this package:
  ```bash
  sudo apt-get update && sudo apt-get install -y git
  ```
  The runtime requirements are **JDK 21 (LTS)** for the KAWA server and workflow engine, and **Python 3.12 or above** for the script runner. On Ubuntu the installer installs them for you through APT (along with Postgres and ClickHouse); on other distributions, install them beforehand.
- **docker mode**: any Linux with an account with sudo, plus git, docker + docker compose, python3 with venv, and openssl. On Ubuntu:
  ```bash
  sudo apt-get update && sudo apt-get install -y git docker.io docker-compose-v2 python3-venv openssl
  ```

### Hardware

- **RAM**: for small data volumes (up to ~200 GB compressed), as much memory as data; 128 GB+ recommended for large interactive workloads.
- **CPU**: the more the better; 64+ cores recommended for hundreds of millions / billions of rows. AMD64 only.
- **Storage**: SSD preferred. Make sure the data partition (native: `/var/lib/kawa` + database directories; docker: the data directory you choose at install time) has enough space.


## 2. Installation procedure

1) Clone this repository on the target machine:
```bash
git clone https://github.com/kawa-analytics/kawa-install.git
cd kawa-install
```

2) Run the installer as root:
```bash
sudo ./install.sh
```

The interactive CLI walks you through everything:

- **Installation mode** — native or docker (or pass `--mode=native` / `--mode=docker`).
- **Registry access** — your GitLab token name and value, stored in `configuration/kawa-registry.credentials`.
- **Version** — exact JAR version in native mode (eg. `1.35.1`), image tag in docker mode (eg. `1.35.x`). Persisted in `kawa.config`.
- **Admin password** — for the `setup-admin@kawa.io` account (with confirmation), stored in the `admin.pwd` file and applied on the server during step 3.
- **native mode only**: the ClickHouse package asks you to set a password for its `default` (system) user; the installer asks for it again to create the KAWA database user. Keep it safe.
- **docker mode only**: the data directory — the mountpoint of all the docker volumes. Back it up daily.

For unattended installations:
```bash
sudo ./install.sh --mode=docker --interactive=false
```
(requires `configuration/kawa-registry.credentials` to be filled in beforehand)

3) Connect from a browser on the configured port (8080 by default) and log in with `setup-admin@kawa.io` and the password you chose.

<p align="center">
  <img  src="readme-assets/login.png" alt="Login page">
</p>

4) Upload your KAWA license, following the [KYWY documentation](https://github.com/kawa-analytics/kywy-documentation) and the [initial setup notebook](https://github.com/kawa-analytics/kywy-documentation/blob/main/notebooks/administration/02_initial_instance_configuration.ipynb).


## 3. Configuration

### How it works: environment variables vs Configuration objects

KAWA is configured through two complementary mechanisms, in both modes:

- **Environment variables**: bootstrap values and secrets. The user-facing values are split between `kawa.config` (nothing secret) and `kawa.secrets` (only secrets). In native mode the live copies are in `/etc/kawa/`; in docker mode the installer bakes them into the generated `docker/.env`.
- **Configuration objects**, stored inside KAWA's database and applied at runtime through the commands API: features, email provider, SMTP server settings, OIDC client, workflow engine, AI. With the kywy python client:
  ```python
  kawa.commands.replace_configuration('<ConfigurationType>', {...payload...})
  ```

The configure step (`sudo ./install.sh --mode=configure`) wraps the second mechanism: it reads `kawa.config`, logs in as the admin, and applies all the Configuration objects. You never need to write python for the standard setup.

> **⚠ Precedence rule:** a Configuration object provided through an environment variable (e.g. `KAWA_STANDALONE_API_SERVER_CONFIGURATION`) always **overrides** the stored one. The environment files deliberately do not define them — do not add them, or the configure step will have no effect.

### 3.a Emails - SMTP (optional)

By default emails are disabled (`LOG`: they are only printed in the server logs). All emails are sent by the KAWA server — **the workflow engine requires no SMTP configuration of its own**.

In `kawa.config`:
```bash
COMMUNICATION_PROVIDER_TYPE=SMTP     # or LOG to disable emails (default)
SMTP_HOST="smtp.wayne.com"
SMTP_PORT=465
SMTP_SSL=true
SMTP_START_TLS=false
SMTP_AUTHENTICATION=true
```

In `kawa.secrets`:
```bash
SMTP_USERNAME="user"
SMTP_PASSWORD="password"
```

Then apply + restart (see the cycle above).

Under the hood: the credentials are passed as the `KAWA_SMTP_USERNAME` / `KAWA_SMTP_PASSWORD` environment variables; the provider type is part of the `StandaloneApiServerConfiguration` object; the host/port/encryption settings are the `SmtpConfig` object.

> **docker mode note:** the environment secrets are baked into `docker/.env` at install time. If you change them later, update both `kawa.secrets` and `docker/.env`, then `docker compose up -d`.

### 3.b Authentication: native KAWA or OIDC / SSO

Two authentication mechanisms are supported:

- **native KAWA** (the default): users log in with an email and a password, managed and verified by KAWA. Nothing to configure.
- **OIDC / SSO** (optional): users authenticate against your identity provider, in addition to the native login.

Any OIDC-compliant identity provider works (Auth0, OKTA, Cognito, Entra ID, Keycloak...). Create a **web application** integration on your provider with:

- the **authorization code** grant enabled, plus **refresh tokens**;
- the scopes KAWA requests: **`openid`, `profile`, `email`, and `offline_access`** (offline access is how KAWA obtains refresh tokens; it is requested by default);
- users must have a **verified email** on the provider: KAWA identifies them by email and rejects unverified ones by default.

From that integration you need three values: the **client id**, the **client secret**, and the **OpenID issuer** URL (the base URL exposing `/.well-known/openid-configuration`).

In `kawa.config`:
```bash
USE_OIDC=true
OIDC_CLIENT_ID="0oa1b2c3d4"
OIDC_ISSUER="https://mycompany.okta.com/oauth2/default"
OIDC_CLIENT_HOST=""                # defaults to KAWA_EXTERNAL_URL
```

In `kawa.secrets`:
```bash
OIDC_CLIENT_SECRET="****"
```

Then apply + restart.

Under the hood: the secret is passed as the `KAWA_OAUTH2_CLIENT_SECRET` environment variable; the rest is the `OAuth2ClientConfiguration` object (`clientId`, `openidIssuer`, `clientHost`).

### 3.c HTTPS - TLS termination (optional)

By default the server listens in plain HTTP — put it behind your reverse proxy for TLS, or terminate TLS on the KAWA server itself. In `kawa.config`:

```bash
USE_HTTPS=true
PATH_TO_SERVER_CERTIFICATE=/path/to/server.crt
PATH_TO_SERVER_PRIVATE_KEY=/path/to/server.key
```

- **native**: the server reads the certificate and key from those paths — make them readable by the `kawa-system` user (mode 600), then `sudo systemctl restart kawa`.
- **docker**: set `USE_HTTPS` **before** installing — the installer copies the files next to the compose file and mounts them into the server container.

HTTPS is entirely environment-driven (no Configuration object). Secure cookies are switched on automatically.

### 3.d File store

The file store contains everything users upload (CSV files, scripts...). It is environment-driven (`KAWA_FILE_STORE_DIRECTORY`):

- **native**: `/var/lib/kawa/files` (set in `/etc/kawa/kawa.env`).
- **docker**: the `kawadata` volume, under the data directory chosen at install time.

Make sure the underlying partition has enough space, and include it in your backups. Extra JDBC drivers can be dropped in `/var/lib/kawa/drivers` (native mode) — KAWA loads them at startup.

### 3.e Python package registry (optional)

The script runner downloads python packages to package the dependencies of user scripts — from **pypi.org** by default. In restricted environments, point it at a private registry or mirror (Nexus, Artifactory...):

In `kawa.config`:
```bash
USE_CUSTOM_PYPI=true
```

In `kawa.secrets` (the url may contain credentials):
```bash
PIP_INDEX_URL="https://user:password@nexus.wayne.com/repository/pypi/simple"
```

Under the hood this sets `KW_PEX_USE_PIP_CONFIG=true` on the script runner, which makes its packaging tool (pex) honor the standard pip configuration — so any other pip setting (`pip.conf`, extra index, trusted hosts...) works too.

### 3.f Features

Features are toggled by the `enabledFeatures` list of the `StandaloneApiServerConfiguration` object, driven by `ENABLED_FEATURES` in `kawa.config`:

```bash
ENABLED_FEATURES="data-samples,list-principals,scripts,dashboard-export"
```

This installation exposes the following features by default:

| Feature            | Description                                          |
|--------------------|------------------------------------------------------|
| `data-samples`     | Data samples                                         |
| `list-principals`  | Users can list the other users (e.g. when sharing)   |
| `scripts`          | Python scripts (requires the script runner)          |
| `dashboard-export` | Dashboard exports                                    |

Then apply + restart.

**AI is completely disabled** in this deployment: the `ai-support` feature is not enabled, and the configure step keeps the LLM configuration (`OpenAiConfiguration`) deactivated.

### 3.g Admin password

The admin account is `setup-admin@kawa.io`. Its password lives in the `admin.pwd` file (native: `/etc/kawa/admin.pwd`; docker: `configuration/admin.pwd` — mode 600) and is applied by the configure step (command `AdminChangeUserPassword`). To change it:

```bash
sudo sh -c 'printf "%s" "my-new-password" > /etc/kawa/admin.pwd'   # native
sudo ./install.sh --mode=configure
```

### 3.h Going further with kywy

Any other Configuration object can be applied manually with the kywy client (venv at `/var/lib/kawa/kywy-venv` in native mode, `./kywy-venv` in docker mode):

```python
from kywy.client.kawa_client import KawaClient

kawa = KawaClient(kawa_api_url='http://localhost:8080')
kawa.login_with_credential(login='setup-admin@kawa.io', password_file='/etc/kawa/admin.pwd')
kawa.commands.replace_configuration('GlobalAuthenticationConfiguration', {
    'authorizedDomains': ['wayne.com'],
})
```

For recurring scripted administration, kywy also supports the environment-based pattern: set `KAWA_API_URL`, `KAWA_API_KEY` (generated from your admin profile in the KAWA GUI) and `KAWA_WORKSPACE`, then use `KawaClient.load_client_from_environment()` — see the [KYWY documentation](https://github.com/kawa-analytics/kywy-documentation).


## 4. Exploitation

### 4.a Native mode

The KAWA server, the workflow engine and the python runner run as systemd services under the `kawa-system` user:

```bash
sudo systemctl status kawa
sudo systemctl status kawa-python-runner
sudo systemctl status kawa-workflow
```

Log files are in `/var/log/kawa` (`kawa-standalone.log`, `kawapythonserver.log`, `kawa-workflow.log`).

Configuration is in `/etc/kawa` (`kawa.config`, `kawa.secrets`, `kawa.env`, `workflow.env`). User data is in `/var/lib/kawa`.

For backups, cover: `/var/lib/kawa`, `/etc/kawa` (the secrets!), the Postgres databases `kawa` and `workflow`, and the ClickHouse database `kawa`.

__Upgrading__: set `KAWA_JAR_VERSION` in `/etc/kawa/kawa.config`, then:

```bash
sudo systemctl stop kawa kawa-workflow
sudo rm /var/lib/kawa/kawa.jar /var/lib/kawa/workflow.jar
sudo systemctl start kawa kawa-workflow    # re-downloads the JARs
```

### 4.b Docker mode

All the services run under docker compose, from the `docker/` directory:

```bash
cd docker
sudo docker compose ps
sudo docker compose logs -f kawa-server
sudo docker compose restart kawa-server
```

The generated `docker/.env` holds this installation's environment (secrets included) — never delete or regenerate it on an existing installation.

For backups, cover the data directory chosen at install time (`pgdata`, `clickhousedata`, `kawadata`) and `docker/.env`.

__Upgrading__: edit `KAWA_BRANCH_NAME` in `docker/.env`, then:

```bash
cd docker
sudo docker compose pull
sudo docker compose --profile clickhouse up -d
```


## 5. What is intentionally NOT in this deployment

- **Riyu (AI co-builder) and all AI features** — no AI components, no LLM credentials, no identity provider required. The `OpenAiConfiguration` is kept deactivated by the configure step.
- **External warehouses** — this is the simple standalone install: always the bundled ClickHouse + Postgres.
- **Other authentication mechanisms** — only native KAWA login and OIDC are supported (section 3.b).
- **HTTPS termination by default** — enable it in `kawa.config` (section 3.c) or terminate TLS on a reverse proxy.
