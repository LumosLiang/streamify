#!/usr/bin/env bash
# Start or deallocate only the five Streamify VMs defined in terraform/main.tf.
# Preview: bash scripts/stop_compute.sh start --dry-run
# Start: bash scripts/stop_compute.sh start
# Stop: bash scripts/stop_compute.sh stop
# No resource deletion. Disks, public IPs and storage remain billable after stop.
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: bash $0 <start|stop> [--dry-run]" >&2
  exit 2
fi
case "$1" in
  start) vm_command=start; expected_state=PowerState/running ;;
  stop) vm_command=deallocate; expected_state=PowerState/deallocated ;;
  *) echo "Usage: bash $0 <start|stop> [--dry-run]" >&2; exit 2 ;;
esac
if [[ $# -eq 2 && "$2" != --dry-run ]]; then
  echo "Usage: bash $0 <start|stop> [--dry-run]" >&2
  exit 2
fi
command -v az >/dev/null || { echo 'Azure CLI is required.' >&2; exit 1; }
dry_run="${2:-}"
subscription_id="$(az account show --query id --output tsv)"
if [[ -z "$subscription_id" ]]; then
  echo 'No active subscription. Run az login and az account set first.' >&2
  exit 1
fi

echo 'Target subscription:'
az account show --subscription "$subscription_id" --query '{Name:name,ID:id}' --output table
# Keep this allowlist aligned with terraform/main.tf. Never enumerate the subscription.
resource_group="streamify-rg"
vm_names=(
  streamify-kafka
  streamify-airflow
  streamify-spark-master
  streamify-spark-worker-1
  streamify-spark-worker-2
)

failed=0
for vm_name in "${vm_names[@]}"; do
  vm_id="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Compute/virtualMachines/${vm_name}"
  if [[ "$dry_run" == --dry-run ]]; then
    printf 'Would %s: %s\n' "$vm_command" "$vm_id"
    continue
  fi
  printf '%s: %s\n' "$vm_command" "$vm_id"
  # Wait for each operation; continue with other VMs if one fails.
  if ! az vm "$vm_command" --subscription "$subscription_id" --ids "$vm_id" --only-show-errors; then
    printf 'FAILED: %s\n' "$vm_id" >&2
    failed=1
    continue
  fi
  if ! power_state="$(az vm get-instance-view --subscription "$subscription_id" --ids "$vm_id" \
    --query "instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]" --output tsv)"; then
    printf 'Could not verify: %s\n' "$vm_id" >&2
    failed=1
  elif [[ "$power_state" != "$expected_state" ]]; then
    printf 'Unexpected state: %s (%s; expected %s)\n' "$vm_id" "$power_state" "$expected_state" >&2
    failed=1
  else
    printf 'Verified: %s (%s)\n' "$vm_id" "$power_state"
  fi
done

if [[ "$dry_run" == --dry-run ]]; then
  echo 'Preview only. No VM states were changed.'
elif [[ "$failed" -eq 0 ]]; then
  printf 'All five VMs reached %s.\n' "$expected_state"
  if [[ "$vm_command" == deallocate ]]; then
    echo 'Disks, public IPs and storage still incur charges.'
  fi
else
  echo 'Some operations failed or could not be verified. Check the messages above.' >&2
fi
exit "$failed"
