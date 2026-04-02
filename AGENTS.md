# AI Agent Instructions — GCP Reverse DNS Lab

This file provides context for AI coding assistants (Claude Code, GitHub Copilot, Gemini,
Amazon Kiro, Cursor, etc.) to understand and implement this project correctly.

---

## What This Project Does

Automated reverse DNS (PTR record) management for a GCP Shared VPC. When a VM or Load
Balancer is created or deleted anywhere in designated GCP folders, a PTR record is
automatically created or removed in Cloud DNS — no manual DNS management needed.

**Problem it solves:** GCP's built-in managed reverse lookup zones only cover VMs in the
same project. They don't cover Load Balancers, Workbench instances, or VMs in Shared VPC
service projects. This project replaces that with a real solution that covers everything.

---

## Architecture

```
GCP Folder (ADC + Common, include_children=true)
    │
    │  Compute Engine audit logs:
    │  instances.insert/delete
    │  forwardingRules.insert/delete
    │  globalForwardingRules.insert/delete
    │
    ▼ (aggregated log sinks — one per folder)
Pub/Sub topic: rrdns-events  (host project)
    │
    ▼ push subscription, OIDC auth
Cloud Run: rrdns-updater  (host project, internal ingress only)
    │
    ▼ rrdnsDnsRecordSetsManager (custom least-privilege role)
Cloud DNS: nonprod-ptr-zone  (10.10.in-addr.arpa.)
```

**Key design decisions — do not change without understanding why:**

1. **Folder-level log sinks, not Eventarc.** Eventarc requires per-project configuration.
   Folder-level sinks with `include_children=true` auto-cover any new project added to the
   folder — zero touch. Never replace these with Eventarc triggers.

2. **Single regular private `/16` DNS zone, not `/24` sub-zones.** Sub-zones shadow the
   parent and break VM PTR resolution. The zone covers all IPs in the CIDR with one zone.

3. **Cloud Run ingress: internal only.** The push subscription uses OIDC authentication.
   Do not change ingress to allow external traffic — the security model relies on this.

4. **`rrdns-cloudrun-sa` has `compute.viewer` at the folder level**, not per-project.
   This means new application projects are automatically covered without IAM changes.

---

## PTR Record Naming Conventions

| Resource type | Pattern | Example |
|---|---|---|
| VM / Workbench | `<name>.<zone>.c.<project>.internal.` | `my-vm.us-central1-a.c.my-project.internal.` |
| Regional ILB | `<name>.<region>.<project>.internal.` | `my-ilb.us-central1.my-project.internal.` |
| Cross-region ILB | `<name>.global.<project>.internal.` | `my-ilb.global.my-project.internal.` |

Vertex AI Workbench instances are Compute Engine VMs — they fire `instances.insert` and
are handled identically to regular VMs.

---

## Repository Structure

```
gcp_rrdns_lab/
├── app/
│   ├── main.py              # Cloud Run Flask app — core event processing logic
│   ├── requirements.txt
│   └── Dockerfile
├── main.tf                  # VPC data source, Cloud DNS zone
├── providers.tf             # google provider (~> 6.0)
├── variables.tf             # project_id, vpc_name, region, zone_ip_prefix, folder IDs
├── apis.tf                  # Enables required GCP APIs in host project
├── iam.tf                   # Service accounts + IAM bindings (folder-level)
├── artifact_registry.tf     # Artifact Registry repo + Docker build (null_resource)
├── cloudrun.tf              # Cloud Run rrdns-updater service
├── pubsub.tf                # Pub/Sub topic, push subscription, log sinks, sink IAM
├── locals.tf                # Shared local values
├── outputs.tf
├── terraform.tfvars.example # Template — copy to terraform.tfvars and fill in
├── AGENTS.md                # This file
├── README.md                # Human-readable documentation + demo commands
└── architecture.html        # Open in browser to view Mermaid diagram locally
```

---

## Prerequisites

Before running Terraform:

1. **GCP account** with an organization (not just a standalone project). The log sinks are
   folder-level — you need at minimum one folder containing your host project.

2. **Two GCP folders:**
   - A "common" folder where the host project lives
   - An "ADC" (application) folder where service projects live
   - Both folder IDs are numeric (e.g., `530060055887`)

3. **Host project** with billing enabled. This is where all infrastructure deploys:
   Cloud Run, Pub/Sub, Cloud DNS, Artifact Registry.

4. **Shared VPC configured** — the host project is the VPC host. At least one subnet
   created in the IP range matching `zone_ip_prefix` (default: `10.10.`).

5. **Tools installed locally:**
   - `gcloud` CLI, authenticated (`gcloud auth application-default login`)
   - `terraform` >= 1.3
   - `docker` (for building the Cloud Run image)

6. **Required GCP permissions** for the identity running Terraform:
   - `roles/owner` on the host project (or equivalent granular roles)
   - `roles/logging.configWriter` on both folders (to create log sinks)
   - `roles/resourcemanager.folderAdmin` on both folders (for IAM bindings)

---

## Deployment Steps

```bash
# 1. Copy and fill in variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set project_id, folder IDs, vpc_name, region

# 2. Authenticate
gcloud auth application-default login
gcloud config set project YOUR_HOST_PROJECT_ID

# 3. Initialize and deploy
terraform init
terraform apply
```

Terraform will:
- Enable required APIs
- Create service accounts and IAM bindings (including folder-level bindings)
- Create the Cloud DNS private zone
- Build and push the Docker image to Artifact Registry
- Deploy the Cloud Run service
- Create the Pub/Sub topic, push subscription, and log sinks

**After apply — required manual step:**
Terraform uses `:latest` image tag. If you later change `app/main.py` and re-apply,
Terraform will rebuild/push the image but will NOT create a new Cloud Run revision
(the image URI hasn't changed). You must redeploy manually:

```bash
gcloud run deploy rrdns-updater \
  --project=YOUR_HOST_PROJECT_ID --region=us-central1 \
  --image=us-central1-docker.pkg.dev/YOUR_HOST_PROJECT_ID/rrdns-updater/rrdns-updater:latest
```

---

## Application Logic (app/main.py)

The Flask app handles one route: `POST /`

**Request flow:**
1. Receive Pub/Sub push envelope (JSON with `message.data` as base64)
2. Decode and parse the GCP audit log inside
3. Route by `protoPayload.methodName`:
   - `instances.insert` → look up VM IP via Compute API → create PTR
   - `instances.delete` → construct FQDN → delete PTR
   - `forwardingRules.insert` → get IP from audit log or Compute API → create PTR
   - `forwardingRules.delete` → construct FQDN → delete PTR
   - `globalForwardingRules.insert/delete` → same, using `.global.` in FQDN

**Environment variables required by the container:**
- `DNS_PROJECT` — GCP project ID where Cloud DNS zone lives
- `DNS_ZONE_NAME` — name of the managed zone (e.g., `nonprod-ptr-zone`)
- `ZONE_IP_PREFIX` — IP prefix to filter (e.g., `10.10.`) — skips IPs outside this range

**Known Cloud DNS API constraint:**
`resourceRecordSets().list()` accepts `name` + `type` together, or `name` alone, but
**not `type` alone** — that returns HTTP 400. The delete function lists all records without
a type filter and searches by FQDN in memory.

---

## IAM Model

| Service Account | Purpose | Key Permissions |
|---|---|---|
| `rrdns-cloudrun-sa` | Runs Cloud Run, calls DNS + Compute APIs | `rrdnsDnsRecordSetsManager` (custom role, record sets only) on host project, `compute.viewer` on both folders |
| `rrdns-pubsub-invoker-sa` | Authenticates push subscription to Cloud Run | `run.invoker` on Cloud Run service |

The push subscription uses OIDC with `rrdns-pubsub-invoker-sa` as the service account.
Cloud Run validates this token automatically via its built-in auth.

---

## Extending the Project

**Adding a new application project:**
1. Add it to the ADC folder — log sinks auto-cover it (no config change)
2. Attach as Shared VPC service project and share subnets
3. `rrdns-cloudrun-sa` already has `compute.viewer` at folder level — no new IAM needed

**Adding a new GCP folder to cover:**
1. Create a new folder-level log sink pointing to the same Pub/Sub topic (see `pubsub.tf`)
2. Grant the sink's service account `pubsub.publisher` on the topic
3. Grant `rrdns-cloudrun-sa` `compute.viewer` on the new folder

**Changing the IP range:**
Update `zone_ip_prefix` in `terraform.tfvars` and update the DNS zone name/suffix in
`main.tf` to match. The zone name in Cloud DNS must match the reverse of your CIDR.

---

## Things to Avoid

- **Eventarc vs folder-level log sinks — choose based on scope:**
  Eventarc is the right choice when you need to react to events in a **single, known project**
  (e.g., trigger a Cloud Run job whenever a specific project's Cloud Storage bucket receives
  a file). It's simple to configure and has first-class Terraform support.

  This project deliberately uses **folder-level aggregated log sinks** instead, because the
  requirement is to cover **all current and future projects across entire GCP folders**. With
  Eventarc, every new application project would need its own trigger wired up manually —
  that's operational overhead and a gap risk if someone forgets. Folder-level sinks with
  `include_children=true` auto-cover any project added to the folder with zero config change.

  If you are adapting this project and your scope is limited to one or two fixed projects,
  Eventarc is a valid and simpler alternative. If your scope spans a folder or org, keep the
  log sink approach.
- **Do not create `/24` PTR sub-zones** — they shadow the parent `/16` zone and break VM
  reverse DNS resolution.
- **Do not change Cloud Run ingress** away from `INGRESS_TRAFFIC_INTERNAL_ONLY`.
- **Do not commit `terraform.tfvars`** — it contains your real project/folder IDs.
- **Do not pass `type=` without `name=`** in `resourceRecordSets().list()` Cloud DNS API
  calls — it returns HTTP 400.
