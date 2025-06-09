#!/bin/bash
set -euo pipefail

# Deploy kubeapply to specified environment via terraform PR
# Usage: deploy-to-env.sh <environment> [create-pr]
#   environment: "stage" or "production" 
#   create-pr: if "true", creates PR automatically; if "false", just prepares branch

ENVIRONMENT=${1:-}
CREATE_PR=${2:-true}

if [[ -z "$ENVIRONMENT" ]]; then
    echo "❌ Error: Environment required (stage or production)"
    exit 1
fi

if [[ "$ENVIRONMENT" != "stage" && "$ENVIRONMENT" != "production" ]]; then
    echo "❌ Error: Environment must be 'stage' or 'production'"
    exit 1
fi

# Get the image tag from git
IMAGE_TAG=$(git describe --tags --always --dirty="-dev")
echo "🏷️  Deploying image tag: $IMAGE_TAG to $ENVIRONMENT"

# Clone terracode-infra repository 
WORK_DIR="/tmp/terracode-infra-$ENVIRONMENT-$$"
git clone https://github.com/segmentio/terracode-infra.git "$WORK_DIR"
cd "$WORK_DIR"

# Configure git user for commits
git config user.email "buildkite-agent-reader@segment.com"
git config user.name "buildkite-kubeapply-pipeline"

# Create a new branch for the deployment
BRANCH_NAME="kubeapply-$ENVIRONMENT-deploy-$IMAGE_TAG-$(date +%s)"
git checkout -b "$BRANCH_NAME"

# Update terraform configs based on environment
if [[ "$ENVIRONMENT" == "stage" ]]; then
    echo "📝 Updating stage terraform configs..."
    sed -i "s/lambda_image_tag.*=.*\".*\"/lambda_image_tag  = \"$IMAGE_TAG\"/" stage/eu-west-1/common-kubeapply/config.tf
    sed -i "s/lambda_image_tag.*=.*\".*\"/lambda_image_tag  = \"$IMAGE_TAG\"/" stage/us-west-2/core/kubeapply/config.tf
    git add stage/*/kubeapply/config.tf stage/*/common-kubeapply/config.tf
    REGIONS="eu-west-1, us-west-2"
elif [[ "$ENVIRONMENT" == "production" ]]; then
    echo "📝 Updating production terraform config..."
    sed -i "s/lambda_image_tag.*=.*\".*\"/lambda_image_tag  = \"$IMAGE_TAG\"/" production/us-west-2/core/kubeapply/config.tf
    git add production/*/kubeapply/config.tf
    REGIONS="us-west-2"
fi

# Commit and push changes
git commit -m "Deploy kubeapply $IMAGE_TAG to $ENVIRONMENT"
git push origin "$BRANCH_NAME"

echo "✅ Branch created and pushed: $BRANCH_NAME"

# Create PR if requested
if [[ "$CREATE_PR" == "true" ]]; then
    echo "🔄 Creating pull request..."
    
    if [[ "$ENVIRONMENT" == "stage" ]]; then
        PR_BODY="Automated deployment of kubeapply image tag \`$IMAGE_TAG\` to stage environment.

**Instructions:**
1. Review the changes in this PR
2. Comment \`atlantis apply\` to deploy to stage environment  
3. Merge this PR after successful deployment

**Image tag:** \`$IMAGE_TAG\`
**Environment:** Stage
**Regions:** $REGIONS"
    else
        PR_BODY="Automated deployment of kubeapply image tag \`$IMAGE_TAG\` to production environment.

**Instructions:**
1. Review the changes in this PR carefully
2. Comment \`atlantis apply\` to deploy to production environment
3. Merge this PR after successful deployment

**Image tag:** \`$IMAGE_TAG\`
**Environment:** Production  
**Region:** $REGIONS"
    fi

    PR_URL=$(gh pr create \
        --title "Deploy kubeapply $IMAGE_TAG to $ENVIRONMENT" \
        --body "$PR_BODY" \
        --head "$BRANCH_NAME" \
        --base master)
    
    echo "✅ Pull request created!"
    echo "🔗 PR URL: $PR_URL"
    echo "📋 Instructions: Go to the PR and comment 'atlantis apply' to deploy to $ENVIRONMENT."
    
    # Add Buildkite annotation with deployment information
    buildkite-agent annotate --style info "🚀 **Deployment PR Created**

📦 **Image tag:** \`$IMAGE_TAG\`  
🌍 **Environment:** $ENVIRONMENT  
🗺️ **Regions:** $REGIONS

🔗 **[View Deployment PR]($PR_URL)**

**Next Steps:**
1. Review the changes in the deployment PR
2. Comment \`atlantis apply\` on the PR to deploy to $ENVIRONMENT
3. Merge the PR after successful deployment"
else
    echo "📋 Branch ready for manual PR creation: $BRANCH_NAME"
    echo "🔗 Create PR at: https://github.com/segmentio/terracode-infra/compare/master...$BRANCH_NAME"
fi