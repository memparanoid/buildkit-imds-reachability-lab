# BuildKit IMDS reachability lab

This lab checks whether an untrusted Dockerfile `RUN` instruction can reach
the AWS Instance Metadata Service address, `169.254.169.254`, through the
default BuildKit network.

It does not contact AWS and contains no real credentials. The lab temporarily
hosts an IMDSv2-compatible server with fake canary credentials on the Docker
worker itself.

## Requirements

- A disposable, non-cloud Linux VM
- Rootful Docker Engine
- Docker Buildx

Colima is not required. It was used during development only as a disposable
Linux VM. Native Linux Docker works as well. Docker Desktop networking may
behave differently.

The mock requires `--network host` and `NET_ADMIN` to temporarily assign
`169.254.169.254/32` inside the Docker host. Do not run the lab on a production
host.

## Run

```console
./run-lab.sh
```

The script creates a temporary Buildx builder and runs two builds:

1. the default `RUN` network;
2. `--network=none` as a negative control.

A positive result looks like this:

```text
RESULT reachable transport=direct role=lab-role access_key=LAB_CANARY_NOT_A_SECRET
```

The negative control should contain:

```text
RESULT unreachable
```

The script asserts both results, prints the fake IMDS request log, and exits
nonzero if the outcome is different. It removes the mock container, temporary
builder, link-local address, and temporary logs on exit. The locally built
`buildkit-imds-mock:local` image is retained for faster subsequent runs.

## What the result means

An IP literal does not use DNS. The relevant behavior is routing: the
BuildKit execution sandbox sends traffic for `169.254.169.254` through its
default route, and the build worker can deliver it to a node-local service.

The mock implements the IMDSv2 token request, IAM role discovery, and role
credential request. It does not emulate AWS's response hop-limit behavior or
the exact hypervisor network path. A platform's practical exposure therefore
also depends on its firewall, worker topology, IMDS configuration, and whether
the worker has an instance role.

`--network=none` is a control, not a practical general mitigation: it also
blocks normal dependency downloads. Buildx's standard `RUN` networking modes
do not provide a policy that allows public Internet access while denying
link-local and private destinations. Selective egress requires an operator
control such as host firewall rules, CNI policy, a filtering proxy, or isolated
workers without cloud credentials.

## Files

- `run-lab.sh`: orchestration, assertions, and cleanup
- `mock_imds.py`: local IMDSv2-compatible server
- `probe.py`: direct and proxy-aware IMDSv2 probe
- `Dockerfile.mock`: mock server image
- `Dockerfile.probe`: untrusted-build simulation
