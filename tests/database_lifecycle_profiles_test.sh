#!/usr/bin/env bash
# Validate database-lifecycle module and optionally cross-check JSON with orchestrator parser.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="${ROOT}/modules/database-lifecycle"
ORCHESTRATOR_ROOT="${ORCHESTRATOR_ROOT:-}"

if ! command -v terraform >/dev/null 2>&1; then
	echo "database_lifecycle_profiles_test: terraform is required" >&2
	exit 1
fi

(
	cd "${MODULE}"
	terraform init -backend=false -input=false >/dev/null
	terraform validate
)

profiles_json="$(
	cd "${MODULE}"
	terraform console -var-file=tests/minimal.tfvars -input=false <<'EOF'
jsonencode(local.lifecycle_profile)
EOF
)"

if ! command -v jq >/dev/null 2>&1; then
	echo "skip: jq not installed; terraform validate passed" >&2
	exit 0
fi

echo "${profiles_json}" | jq -e '.environments | length > 0' >/dev/null
echo "${profiles_json}" | jq -e '.profiles | length > 0' >/dev/null
echo "${profiles_json}" | jq -e '.moduleSelectors.ensure_database.source != ""' >/dev/null
echo "${profiles_json}" | jq -e '.moduleSelectors.ensure_database.baseInputs.credential_secret_prefix != ""' >/dev/null
echo "${profiles_json}" | jq -e '.moduleSelectors.ensure_physical_database_instance.source != ""' >/dev/null
echo "${profiles_json}" | jq -e '(.supportedOperations | index("migrate_schema")) != null' >/dev/null
echo "${profiles_json}" | jq -e '(.moduleSelectors | has("migrate_schema")) | not' >/dev/null

if [[ -n "${ORCHESTRATOR_ROOT}" && -d "${ORCHESTRATOR_ROOT}/pkg/databaselifecycle" ]]; then
	wrapped="$(jq -cn --argjson profile "${profiles_json}" '[ $profile ]')"
	(
		cd "${ORCHESTRATOR_ROOT}"
		TEST_PROFILES_JSON="${wrapped}" go test ./pkg/databaselifecycle/... -run TestLifecycleConfigFromProfilesFromEnvJSON -count=1
	)
fi
