# Learn to Cloud Phase 3 Capstone: Journal API

[![CI](https://github.com/githukueliud/journal-starter/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/githukueliud/journal-starter/actions/workflows/ci.yml)

Welcome to [Learn to Cloud's](https://learntocloud.com) Phase 3 capstone. You will be guided to building a journal API with **FastAPI**, **PostgreSQL**, structured logging, input validation, and AI-powered entry analysis.

## Capstone

These chapters will guide you and are meant to be completed in order. Each chapter builds on the previous one, so do not skip ahead. 

1. [Check the prerequisites](docs/01-prerequisites.md)
2. [Set up the project](docs/02-project-setup.md)
3. [Run the API](docs/03-run-the-api.md)
4. [Build GET for one entry](docs/04-get-entry.md)
5. [Build DELETE for one entry](docs/05-delete-entry.md)
6. [Add input validation and debug a partial update](docs/06-input-validation.md)
7. [Use logs to understand the API](docs/07-logging.md)
8. [Set up an AI provider](docs/08-ai-setup.md)
9. [Build AI-powered analysis](docs/09-ai-analysis.md)
10. [Finish the capstone](docs/10-finish.md)

**[Start the capstone →](docs/01-prerequisites.md)**

## Reference

This is additional reference material for the capstone in case you want to explore further or need help:

- [Testing and CI](docs/reference/testing-and-ci.md)
- [Troubleshooting](docs/reference/troubleshooting.md)
- [Sync your fork with upstream](docs/reference/upstream-sync.md)
- [Explore your database](docs/reference/explore-database.md)

> **Learning environment only:** This application has no authentication or
> per-user data isolation. Do not expose it publicly or store personal or
> sensitive journal content in it.

## Deployment Architecture & Evidence (Phase 4 Capstone)

### 1. Architecture Diagram

```mermaid
flowchart TB
    client["Public Clients / Verifier"]
    admin["Admin (Google Cloud SDK / IAP)"]
    ai["AI Provider (OpenAI Responses API)"]

    subgraph gcp["Google Cloud Platform (VPC: journal-vpc)"]
        subgraph public_subnet["Public Tier (journal-public-subnet: 10.10.1.0/24)"]
            app["App VM (journal-app-vm)<br/>Public IP: 34.171.17.42<br/>Nginx + Certbot HTTPS (Let's Encrypt)<br/>FastAPI / Uvicorn Service (systemd)"]
        end

        subgraph private_subnet["Private Tier (journal-private-subnet: 10.10.2.0/24)"]
            db["Database VM (journal-db-vm)<br/>Private IP: 10.10.2.2<br/>PostgreSQL 14/15<br/>No Public IP"]
        end

        nat["Cloud NAT (journal-nat)<br/>Cloud Router (journal-router)"]
    end

    client -->|"HTTPS 443 (Trusted Let's Encrypt)"| app
    app -->|"TCP 5432 (Internal Subnet Only)"| db
    private_subnet -.-> nat
    nat -.->|"Outbound Updates"| gcp
    app -->|"HTTPS Egress"| ai
    admin -->|"SSH via IAP Tunneling (35.235.240.0/20)"| app
    admin -->|"SSH via IAP Tunneling (35.235.240.0/20)"| db
```

### 2. Selected Services & Deployment Controls

- **Cloud Provider:** Google Cloud Platform (GCP)
- **Deployment Tool:** HashiCorp Terraform (`deploy/terraform/main.tf`)
- **Compute Tier:**
  - `journal-app-vm` (`e2-micro`, Ubuntu 22.04 LTS): Hosts Nginx reverse proxy, Certbot SSL certificate manager, and the FastAPI Uvicorn service under systemd.
  - `journal-db-vm` (`e2-micro`, Ubuntu 22.04 LTS): Hosts standalone PostgreSQL. Has **no external IP address** and resides purely in the private subnet.
- **Networking & Access Controls:**
  - **Custom VPC (`journal-vpc`):** Separated into `journal-public-subnet` (`10.10.1.0/24`) and `journal-private-subnet` (`10.10.2.0/24`).
  - **Firewall Rules:**
    - `journal-allow-http-https`: Allows ingress on ports 80 and 443 from `0.0.0.0/0` to `journal-app` only.
    - `journal-allow-app-to-db`: Restricts port 5432 ingress on `journal-db` strictly to source range `10.10.1.0/24`. Direct internet access to the database is completely blocked.
    - `journal-allow-ssh-admin`: Restricts SSH (port 22) exclusively to Google Cloud Identity-Aware Proxy (`35.235.240.0/20`), requiring authenticated IAM credentials.
- **AI Model & Safety Controls:**
  - **Model:** `openai/gpt-4o-mini` accessed via standard OpenAI Responses API format with strict JSON Schema constraints (`sentiment`, `summary`, and `topics` minItems: 2, maxItems: 4).
  - Credentials injected securely through environment files, excluded from source control and logs.
- **Estimated Cost:**
  - 2x `e2-micro` instances: ~$0.01 - $0.02 per hour (Free Tier eligible).
  - Cloud NAT + Static IP: ~$0.01 per hour.
  - Budget alert threshold configured in GCP Billing console.

### 3. Verification & Deployment Evidence

- **Public HTTPS Base URL:** `https://34.171.17.42.sslip.io`
- **Certificate Authority:** Let's Encrypt (Trusted SSL Certificate, valid through 2027-02-18)
- **Constraint Demonstration:**
  1. **Public HTTPS:** `curl -i https://34.171.17.42.sslip.io/docs` returns HTTP `200 OK` over TLS.
  2. **Database Isolation:** Database accepts connections from `10.10.1.0/24` only. Direct connection attempts from the public internet time out (`nc -zv -w 3 10.10.2.2 5432` / `nc -zv -w 3 34.171.17.42 5432` timed out).
  3. **Private Management:** Port 22 is closed to the public internet; admin access uses authenticated GCP IAP tunnels.
  4. **Persistence & Reliability:** Application is managed by `systemd` (`journal-api.service`) with `Restart=always`; PostgreSQL persists state to disk across restarts.
  5. **Functional API & Live AI:**
     - `POST /entries` created entry `13300e9f-1ed1-48fb-b957-036a6d9bd582` with status `200`.
     - `POST /entries/13300e9f-1ed1-48fb-b957-036a6d9bd582/analyze` returned sentiment (`positive`), summary, and 4 topics within < 6 seconds.

### 4. Production Limitation & Next Steps

- **Limitation:** Lack of user authentication and data isolation. Every client accessing `https://34.171.17.42.sslip.io/entries` shares a single global journal store without per-user tenancy or role-based access control.
- **Production Solution:** Implement OAuth2 / JWT authentication (e.g. Firebase Auth, Auth0, or Cognito) and associate all journal records with an authenticated `user_id` column with row-level security.

## License

MIT License - see [LICENSE](LICENSE).
