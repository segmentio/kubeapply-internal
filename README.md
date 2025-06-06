# kubeapply

## Contents

  * [Overview](#overview)
  * [Motivation](#motivation)
  * [Getting started](#getting-started)
  * [Configuration](#configuration)
  * [Usage (CLI)](#usage-cli)
  * [Usage (Github webhooks)](#usage-github-webhooks)
  * [Experimental features](#experimental-features)
  * [Testing](#testing)
  * [Internal Repository Synchronization](#internal-repository-synchronization)
  * [CI/CD Process](#ci/cd-process)

## Overview

`kubeapply` is a lightweight tool for git-based management of Kubernetes configs.
It supports configuration in raw YAML, templated YAML,
[Helm charts](https://helm.sh/docs/topics/charts/), and/or [skycfg](https://github.com/stripe/skycfg),
and facilitates the complete change workflow including config expansion, validation,
diff generation, and applying.

It can be run from either the command-line or in a webhooks mode that responds
interactively to Github pull request events:

<img width="823" src="https://user-images.githubusercontent.com/54862872/88240197-4c180200-cc3b-11ea-933d-edf3e15f7e8c.png">

## Motivation

Managing Kubernetes configuration in a large organization can be painful. Existing tools like
[Helm](https://helm.sh/) are useful for certain parts of the workflow (e.g., config generation),
but are often too heavyweight for small, internal services. Once configs are generated, it's hard
to understand what impact they will have in production and then apply them in a consistent way.

We built `kubeapply` to make the end-to-end config management process easier and more
consistent. The design choices made were motivated by the following goals:

1. Support git-based workflows. i.e., can look at a repo to understand the state of a cluster
2. Make it easy to share configuration between different environments (e.g., staging vs. production)
  and cluster types
3. Wrap existing tooling (`kubectl`, `helm`, etc.) whenever possible as opposed to
  reimplementing their functionality
4. Allow running on either the command-line or in Github
5. Support Helm charts, simple templates, and skycfg

See [this blog post](https://segment.com/blog/kubernetes-configuration/) for more details.

### Disclaimer

The tool is designed for our Kubernetes-related workflows at [Segment](https://segment.com).
While we hope it can work for others, not all features might be directly applicable to other
environments. We welcome feedback and collaboration to make `kubeapply` useful to more people!

## 🆕 Terraform version of `kubeapply`

We recently open-sourced a Terraform-provider-based version of this tool; see the
[repository](https://github.com/segmentio/terraform-provider-kubeapply) and
[documentation in the Terraform registry](https://registry.terraform.io/providers/segmentio/kubeapply/latest/docs) for more details.

Note that the Terraform version has slightly different interfaces and assumptions (e.g., no
support for Helm charts), so it's not a drop-in replacement for the tooling here, but it follows
the same general flow and configuration philosophy.

## Getting started

### Prerequisites

`kubeapply` depends on the following tools:

- [`kubectl`](https://kubernetes.io/docs/tasks/tools/install-kubectl/): v1.16 or newer
- [`helm`](https://helm.sh/docs/intro/install/): v3.5.0 or newer (only needed if using helm charts)

Make sure that they're installed locally and available in your path.

### Installing

Install the `kubeapply` binary by running:

```go install github.com/segmentio/kubeapply/cmd/kubeapply@latest```

You can also build and install the binary by running `make install` in the root of this
repo.

### Quick tour

See the [README](/examples/kubeapply-test-cluster/README.md) in the
[`examples/kubeapply-test-cluster`](/examples/kubeapply-test-cluster) directory.

## Configuration

### Repo layout

Each cluster type to be managed by `kubeapply` lives in a directory in a source-controlled
repo. This directory has a set of *cluster configs* and a *profile* that is shared by the former.
A cluster config plus the profile is *expanded* by `kubeapply` to create a set of expanded,
kubectl-compatible YAML configs for the cluster. Although these expanded configs can be derived in
a fully reproducible way from the cluster configs and profile, they're typically checked-in to the
repo for easier code review.

The following diagram shows the recommended directory layout:

```
.
└── clusters
    └── [cluster type]
        ├── expanded
        |   ├── ...
        ├── profile
        │   ├── [namespace 1]
        │   │   ├── [config 1]
        │   │   ├── [config 2]
        │   ├── [namespace 2]
        │   ├── ...
        ├── [cluster config1]
        └── [cluster config2]
```

Each of the subcomponents is described in more detail in the sections below. See also
[`examples/kubeapply-test-cluster`](/examples/kubeapply-test-cluster) for a full example.

### Cluster config

Each cluster instance is configured in a single YAML file. Typically, these instances
will vary by the environment (e.g., staging vs. production) and/or the region/account
in which they're deployed, but will share the same profile. At Segment, we name the files
by the environment and region, e.g., `stage-us-west-2.yaml`, `production-us-west-2.yaml`,
but you can use any naming convention that feels comfortable.

Each cluster config has the following format:

```yaml
# Basic information about the cluster. The combination of these should uniquely identify
# a single cluster instance running in a single location.
cluster: my-cluster    # Name of the cluster
region: us-west-2      # Region in which the cluster is running
env: staging           # Environment/account in which the cluster is running

# Where charts can be found by default. Only required if using Helm chart sources.
# See the section below for the supported URL formats.
charts: "file://../../charts"

# Arbitrary parameters that can be used in templates, Helm charts, and skycfg modules.
#
# These are typically used for things that will vary by cluster instance and/or will
# frequently change, e.g. the number of replicas for deployments, container image URIs, etc.
parameters:
  service1:
    imageTag: abc123
    replicas: 2

  service2:
    imageTag: def678
    replicas: 5
  ...
```

### Profile

The `profile` directory contains source files that are used to generate Kubernetes
configs for a specific cluster. By convention, these files are organized into subdirectories
by namespace, and can be further subdivided below that.

The tool currently supports four kinds of input source configs, described in more detail
below.

#### (1) Raw YAML

Files of the form `[name].yaml` will be treated as normal YAML files and copied to the
`expanded` directory as-is.

#### (2) Templated YAML

Files with names ending in `.gotpl.yaml` will be templated using the
[golang `text/template` package](https://golang.org/pkg/text/template/) with the cluster config
as the input data. You can also use the functions in the
[sprig library](http://masterminds.github.io/sprig/).

See [this file](/examples/kubeapply-test-cluster/profile/apps/echoserver/deployment.gotpl.yaml)
for an example.

Note that template expansion happens before Helm chart evaluation, so you can template Helm
value files as well.

#### (3) Helm chart values

Files named `[chart name].helm.yaml` will be treated as values files for the associated chart.
The chart will be expanded using `helm template ...` and the outputs copied into the `expanded`
directory. See [this file](/examples/kubeapply-test-cluster/profile/apps/envoy/envoy.helm.yaml)
for an example (which references the [envoy chart](/examples/kubeapply-test-cluster/charts/envoy)).

By default, charts are sourced from the URL set in the cluster config `charts` parameter.
Currently, the tool supports URLs of the form `file://`, `http://`, `https://`, `git://`,
`git-https://`, and `s3://`.

You can override the source for a specific chart by including a `# charts: [url]`
comment at the top of the values file. This is helpful for testing out a new version
for just one chart in the profile.

#### (4) Skycfg/starlark modules

Files ending in `.star` will be evaluated using the
[skycfg framework](https://github.com/stripe/skycfg) to generate one or more Kubernetes protobufs.
The latter are then converted to kubectl-compatible YAML and copied into the `expanded` directory.

Skycfg uses the [Starlark](https://github.com/bazelbuild/starlark) language along with typed
Kubernetes structs (from [Protocol Buffers](https://developers.google.com/protocol-buffers/)),
so it can provide more structure and less repetition than YAML-based sources. See
[this file](/examples/kubeapply-test-cluster/profile/apps/redis/deployment.star) for an example.

The skycfg support in `kubeapply` is experimental and unsupported.

### Expanded configs

The `expanded` directory contains the results of expanding out the `profile` for
a cluster instance. These configs are pure YAML that can be applied directly via `kubectl apply`
or, preferably, using the `kubeapply apply` command (described below).

## Usage (CLI)

#### Expand

`kubeapply expand [path to cluster config]`

This will expand out all of the configs for the cluster instance, and put them into
a subdirectory of the `expanded` directory. Helm charts are expanded via `helm template`;
other source types use custom code in the `kubeapply` binary.

#### Validate

`kubeapply validate [path to cluster config] --policy=[path to OPA policy in rego format]`

This validates all of the expanded configs for the cluster using the
[`kubeconform`](https://github.com/yannh/kubeconform) library. It also, optionally, supports
validating configs using one or more [OPA](https://www.openpolicyagent.org/) policies in
rego format; see the "Experimental features" section below for more details.

#### Diff

`kubeapply diff [path to cluster config] --kubeconfig=[path to kubeconfig]`

This wraps `kubectl diff` to show a diff between the expanded configs on disk and the
associated resources in the cluster.

#### Apply

`kubeapply apply [path to cluster config] --kubeconfig=[path to kubeconfig]`

This wraps `kubectl apply`, with some extra logic to apply in a "safe" order
(e.g., configmaps before deployments, etc.).

## Usage (Github webhooks)

In addition to interactions through the command-line, `kubeapply` also supports an
[Atlantis](https://www.runatlantis.io/)-inspired, Github-based workflow for the `diff` and
`apply` steps above. This allows the diffs to be more closely reviewed before being
applied, and also ensures that the configuration in the repo stays in-sync with the cluster.

### Workflow

The end-to-end user flow is fairly similar to the one used with Atlantis for
Terraform changes:

1. Team member changes a cluster config or profile file in the repo, runs
  `kubeapply expand` locally
2. A pull request is opened in Github with the changes
3. Kubeapply server gets webhook from Github, posts a friendly "help" message and then
  runs an initial diff
4. PR owner iterates on change, gets it reviewed
5. When ready, PR owner posts a `kubeapply apply` comment
6. Kubeapply server gets webhook, checks that change has green status and is approved,
  then applies it
7. If all changes have been successfully applied, change is automatically merged

### Backend

Using the Github webhooks flow requires that you run an HTTP service somewhere that is accessible
to Github. Since the requests are sporadic and can be handled without any local state,
processing them is a nice use case for a serverless framework like
[AWS Lambda](https://aws.amazon.com/lambda/), and this is how we run it at Segment. Alternatively,
you can run a long-running server that responds to the webhooks.

The sections below contain some implementation details for each option.

#### Option 1: Run via AWS Lambda

The exact setup steps will vary based on your environment and chosen tooling. At a high-level,
however, the setup process is:

1. Build a lambda bundle by running `make lambda-zip`
2. Upload the bundle zip to a location in S3
3. Generate a Github webhook token and a shared secret that will be used for webhook
  authentication; store these in SSM
4. Using Terraform, the AWS console, or other tooling of your choice, create:
    1. An-externally facing ALB
    2. An IAM role for your lambda function that has access to the zip bundle in S3, secrets in SSM,
      etc.
    3. A security group for your lambda function that has access to your cluster control planes
    4. A lambda function that runs the code in the zip bundle when triggered by ALB requests

The lambda is configured via a set of environment variables that are documented in
the [lambda entrypoint](/cmd/kubeapply-lambda/main.go). We use SSM for storing secrets like
Github tokens, but it's possible to adapt the code to get these from other places.

#### Option 2: Run via long-running server

We've provided a basic server entrypoint [here](/cmd/kubeapply-server/main.go). Build a binary
via `make kubeapply-server`, configure and deploy this on your infrastructure of choice,
and expose the server to the Internet.

### Github configuration

Once you have an externally accessible webhook URL, go to the settings for your repo
and add a new webhook:

<img width="958" src="https://user-images.githubusercontent.com/54862872/88247376-5bef1080-cc52-11ea-83fb-2603dbaccd47.png">

In the "Event triggers" section, select "Issue comments" and "Pull requests" only. Then, test it
out by opening up a new pull request that modifies an expanded kubeapply config.

## Experimental features

### `kubestar`

This repo now contains an experimental tool, `kubestar`, for converting YAML to
skycfg-compatible starlark. See [this README](/cmd/kubestar/README.md) for details.

### Multi-profile support

The cluster config now supports using multiple profiles. Among other use cases, this is useful if
you want to share profile-style YAML templates across multiple clusters without dealing with Helm.

To use this, add a `profiles` section to the cluster config:

```yaml
cluster: my-cluster
...
profiles:
  - name: [name of first profile]
    url: [url for first profile]
  - name: [name of second profile]
    url: [url for second profile]
  ...
```

where the `url`s are in the same format as those for Helm chart locations,
e.g. `file://path/to/my/file`. The outputs of each profile will be expanded into
`[expanded dir]/[profile name]/...`.

### OPA policy checks

The `kubeapply validate` subcommand now supports checking expanded configs against policies in
[Open Policy Agent (OPA)](https://www.openpolicyagent.org/) format. This can be helpful for
enforcing organization-specific standards, e.g. that images need to be pulled from a particular
private registry, that all labels are in a consistent format, etc.

To use this, write up your policies as `.rego` files as described in the OPA documentation and run
the former subcommand with one or more `--policy=[path to policy]` arguments. By default, policies
should be in the `com.segment.kubeapply` package. Denial reasons, if any, are returned by
setting a `deny` variable with a set of denial reason strings. If this set is empty,
`kubeapply` will assume that the config has passed all checks in the policy file.

If a denial reason begins with the string `warn:`, then that denial will be treated as a
non-blocking warning as opposed to an error that causes validation to fail.

See [this unit test](/pkg/validation/policy_test.go) for some examples.

## Testing

### Unit tests

Run `make test` in the repo root.

### On Github changes

You can simulate Github webhook responses by running `kubeapply` with the `pull-request`
subcommand:

```
kubeapply pull-request \
  --github-token=[personal token] \
  --repo=[repo in format owner/name] \
  --pull-request=[pull request num] \
  --comment-body="kubeapply help"
```

This will respond locally using the codepath that would be executed
in response to a Github webhook for the associated repo and pull request.

## Internal Repository Synchronization

This repository is an internal fork of [segmentio/kubeapply](https://github.com/segmentio/kubeapply) that contains our internal CI/CD pipeline configuration. To maintain synchronization with the upstream public repository, follow these steps:

### Adding the Upstream Remote

If you haven't already, add the upstream remote (only needed once):

```bash
git remote add upstream https://github.com/segmentio/kubeapply.git
git remote set-url --push upstream DISABLED  # Prevent accidental pushes to public repo
```

### Syncing Process

1. **Before syncing:**
   - Ensure your local `main` branch is up to date with this internal repository
   - Check that you don't have any uncommitted changes

2. **Sync with upstream:**
   ```bash
   # Update your local copy of the upstream repository
   git fetch upstream

   # Switch to your local main branch
   git checkout main

   # Merge upstream changes
   git merge upstream/main

   # Push changes to the internal repository
   git push origin main
   ```

3. **For specific releases/tags:**
   ```bash
   # Fetch all tags from upstream
   git fetch upstream --tags

   # To sync a specific tag
   git checkout tags/<tag_name> -b sync-<tag_name>
   
   # Push the tag to the internal repository
   git push origin sync-<tag_name>
   ```

### Important Notes

- Always review changes from upstream before pushing to ensure no internal configurations or secrets are overwritten
- The `staging` branch is used for staging deployments and the `main` branch for production
- After syncing, the Buildkite pipeline will automatically trigger to build and validate the changes
- In case of merge conflicts:
  1. Resolve conflicts favoring upstream changes for core functionality
  2. Preserve our internal pipeline configurations and any internal customizations
  3. Document any significant conflict resolutions in the merge commit message

### Troubleshooting

If you encounter issues during synchronization:
1. Never force push to shared branches (`main` or `staging`)
2. If the sync becomes complex, create a new branch and use `git cherry-pick` to selectively apply upstream changes
3. Consult the DevOps team if you're unsure about resolving conflicts between upstream and internal changes

## CI/CD Process

This internal repository includes an automated CI/CD pipeline for building and deploying the `kubeapply-lambda` Docker image. The process is implemented using Buildkite and handles both staging and production deployments.

### Release Process

#### Staging Releases
1. Create a branch from `main` and make your changes
2. Run `make build-lambda-image` locally to test the build
3. Push your changes to a branch and create a pull request
4. Once the PR is approved and merged to the `staging` branch:
   - Buildkite automatically triggers the pipeline
   - Tests are run
   - Lambda image is built and pushed to staging ECR
   - You'll receive a notification with the new image tag to update in Terraform

5. Update Terraform Configuration (Staging):
   ```hcl
   # In terracode-infra/.../staging/config.tf
   module "kubeapply_lambda" {
     source = "..."
     lambda_image_tag = "v1.2.3-dev"  # Use the tag from the pipeline notification
   }
   ```

#### Production Releases
1. After testing in staging, merge the `staging` branch to `main`
2. The Buildkite pipeline will:
   - Run tests again
   - Build and push the Lambda image to production ECR
   - Provide the image tag for Terraform updates

3. Update Terraform Configuration (Production):
   ```hcl
   # In terracode-infra/.../production/config.tf
   module "kubeapply_lambda" {
     source = "..."
     lambda_image_tag = "v1.2.3"  # Use the tag from the pipeline notification
   }
   ```

### Image Tagging Strategy

The image tags are derived from the public repository's git tags to maintain traceability:

- Format: `v{major}.{minor}.{patch}[-dev]`
- Examples:
  - `v1.2.3` - Release version from a tagged commit
  - `v1.2.3-dev` - Development version with uncommitted changes
  - `abc123de` - Short commit SHA if no version tag is available

To trace an image back to its source:
1. Find the image tag from the ECR repository or Terraform configuration
2. If it's a version tag (e.g., `v1.2.3`):
   ```bash
   git fetch upstream --tags
   git checkout tags/v1.2.3
   ```
3. If it's a commit SHA:
   ```bash
   git fetch upstream
   git checkout abc123de
   ```

### Rollback Procedures

If you need to rollback a deployment:

1. **Find the Previous Stable Version:**
   ```bash
   # List previous deployments in Terraform state
   terraform state show module.kubeapply_lambda
   ```
   Or check ECR for the previous image tag.

2. **Update Terraform Configuration:**
   ```hcl
   module "kubeapply_lambda" {
     source = "..."
     lambda_image_tag = "v1.2.2"  # Previous stable version
   }
   ```

3. **Apply the Change:**
   ```bash
   # For staging
   terraform workspace select staging
   terraform plan    # Verify the changes
   terraform apply   # Apply the rollback

   # For production
   terraform workspace select production
   terraform plan    # Verify the changes
   terraform apply   # Apply the rollback
   ```

4. **Verify the Rollback:**
   - Check AWS Lambda console to confirm the function is using the previous image
   - Monitor application logs and metrics
   - Verify the Lambda function is responding to GitHub webhooks correctly

5. **Document the Rollback:**
   - Create a post-mortem issue
   - Document the reason for rollback
   - Track any fixes needed before re-attempting the upgrade
