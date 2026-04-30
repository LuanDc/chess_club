# Task 02: Oracle Object Storage Setup

> RFC reference: §8.5 — Oracle Object Storage
> Depends on: Task 01 (Oracle Cloud account and VM must exist)

## Goal

Create the private Object Storage bucket that stores versioned OTP release artefacts and the `current.json` deployment manifest. DeployEx polls this manifest to detect new releases; GitHub Actions writes to it. Both must have the correct IAM permissions before the CI/CD pipeline (Task 04) or DeployEx (Task 05) can function.

## Checklist

- [ ] Navigate to Oracle Cloud Console → Object Storage → Buckets
- [ ] Create a new bucket named `chess-releases`:
  - [ ] Visibility: **Private**
  - [ ] Storage tier: Standard
  - [ ] Note down the bucket namespace and region (needed in later tasks)
- [ ] Create an OCI IAM policy for the VM instance principal:
  - [ ] Create a Dynamic Group that matches the VM instance OCID
  - [ ] Write a policy granting the Dynamic Group `manage objects` in the `chess-releases` bucket
  - [ ] Verify the VM can access the bucket: `oci os object list --bucket-name chess-releases`
- [ ] Generate an OCI API key pair for GitHub Actions:
  - [ ] Create an IAM user dedicated to CI (e.g. `github-actions-chess`)
  - [ ] Attach a policy with least-privilege: `object put` and `object get` on `chess-releases` only
  - [ ] Generate an API signing key for this user; download the private key (`.pem`)
  - [ ] Note the user OCID, tenancy OCID, fingerprint, and region
- [ ] Store secrets in GitHub Actions repository secrets:
  - [ ] `OCI_CLI_KEY` — contents of the `.pem` private key
  - [ ] `OCI_TENANCY` — tenancy OCID
  - [ ] `OCI_USER` — IAM user OCID
  - [ ] `OCI_FINGERPRINT` — API key fingerprint
  - [ ] `OCI_REGION` — OCI region identifier (e.g. `eu-frankfurt-1`)
- [ ] Verify bucket access from a local machine using the GitHub Actions credentials (dry-run of `oci os object put`)
- [ ] Document the following values for use in Tasks 04 and 05:
  - [ ] Bucket name: `chess-releases`
  - [ ] Bucket namespace: `<namespace>`
  - [ ] Region: `<region>`
  - [ ] Object Storage base URL: `https://objectstorage.<region>.oraclecloud.com/n/<namespace>/b/chess-releases/o/`

## Notes / References

- Oracle Object Storage is free up to 20 GB under the Always Free programme
- The `current.json` format expected by DeployEx: `{"version": "<sha>", "url": "<presigned-or-direct-url>"}`
- Artefact retention: consider keeping the last 5 releases for rollback safety; older ones can be deleted manually or via a lifecycle policy
- OCI CLI installation: `pip install oci-cli` or use the official installer
