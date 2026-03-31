# Claude Code Instructions

See [AGENTS.md](AGENTS.md) for full project context, architecture, deployment steps, and constraints.

## Claude-specific preferences
- Always query the Terraform registry for the latest `google-beta` provider version before generating any new `.tf` files.
- Run `terraform validate` after generating Terraform code, then `terraform plan` only if validation passes.
- Never use Eventarc — use folder-level log sinks (see AGENTS.md).
