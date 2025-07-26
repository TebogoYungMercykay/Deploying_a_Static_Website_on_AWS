#!/bin/bash

# AWS S3 Deployment Script
# Usage: ./deploy.sh [OPTIONS]

set -e  # Exit on any error

# Default values
BUCKET_NAME=""
STACK_NAME=""
REGION="us-east-1"
POLICY_TYPE="bucket"
DRY_RUN=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# File paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICIES_DIR="$SCRIPT_DIR/../policies"
CLOUDFORMATION_DIR="$SCRIPT_DIR/../cloudformation"

BUCKET_POLICY_FILE="$POLICIES_DIR/s3-bucket-policy.json"
OBJECT_POLICY_FILE="$POLICIES_DIR/s3-object-policy.json"
CLOUDFORMATION_FILE="$CLOUDFORMATION_DIR/s3-bucket-template.json"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
AWS S3 Deployment Script

USAGE:
    ./deploy.sh [OPTIONS]

OPTIONS:
    -b, --bucket-name NAME      S3 bucket name (required for policy deployment)
    -s, --stack-name NAME       CloudFormation stack name (required for CF deployment)
    -r, --region REGION         AWS region (default: us-east-1)
    -p, --policy-type TYPE      Policy type: bucket|object|both (default: bucket)
    -d, --dry-run              Show what would be done without executing
    -v, --verbose              Enable verbose output
    -h, --help                 Show this help message

COMMANDS:
    ./deploy.sh deploy-policy   Deploy S3 bucket policy
    ./deploy.sh deploy-cf       Deploy CloudFormation template
    ./deploy.sh deploy-all      Deploy both policy and CloudFormation
    ./deploy.sh validate        Validate all files
    ./deploy.sh cleanup         Delete stack and remove policies

EXAMPLES:
    ./deploy.sh deploy-policy -b my-bucket-name -p bucket
    ./deploy.sh deploy-cf -s my-stack-name
    ./deploy.sh deploy-all -b my-bucket-name -s my-stack-name
    ./deploy.sh validate
    ./deploy.sh cleanup -b my-bucket-name -s my-stack-name

EOF
}

check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    log_success "AWS CLI is configured and working"
}

check_files() {
    local missing_files=()
    
    if [[ ! -f "$BUCKET_POLICY_FILE" ]]; then
        missing_files+=("$BUCKET_POLICY_FILE")
    fi
    
    if [[ ! -f "$OBJECT_POLICY_FILE" ]]; then
        missing_files+=("$OBJECT_POLICY_FILE")
    fi
    
    if [[ ! -f "$CLOUDFORMATION_FILE" ]]; then
        missing_files+=("$CLOUDFORMATION_FILE")
    fi
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_error "Missing files:"
        for file in "${missing_files[@]}"; do
            echo "  - $file"
        done
        exit 1
    fi
    
    log_success "All required files found"
}

validate_json() {
    local file="$1"
    local name="$2"
    
    if ! python3 -m json.tool "$file" > /dev/null 2>&1; then
        log_error "$name has invalid JSON syntax"
        return 1
    fi
    
    log_success "$name JSON is valid"
    return 0
}

substitute_variables() {
    local file="$1"
    local bucket_name="$2"
    local key_name="${3:-*}"
    
    sed "s/\${BucketName}/$bucket_name/g; s/\${KeyName}/$key_name/g" "$file"
}

deploy_bucket_policy() {
    local bucket_name="$1"
    local policy_file="$2"
    
    log_info "Deploying bucket policy to $bucket_name..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy policy from $policy_file"
        return 0
    fi
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$bucket_name" --region "$REGION" 2>/dev/null; then
        log_error "Bucket $bucket_name does not exist or is not accessible"
        return 1
    fi
    
    # Substitute variables and deploy policy
    local temp_policy=$(mktemp)
    substitute_variables "$policy_file" "$bucket_name" > "$temp_policy"
    
    if aws s3api put-bucket-policy --bucket "$bucket_name" --policy "file://$temp_policy" --region "$REGION"; then
        log_success "Bucket policy deployed successfully"
        rm "$temp_policy"
        return 0
    else
        log_error "Failed to deploy bucket policy"
        rm "$temp_policy"
        return 1
    fi
}

deploy_cloudformation() {
    local stack_name="$1"
    
    log_info "Deploying CloudFormation stack: $stack_name..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy CloudFormation stack $stack_name"
        return 0
    fi
    
    # Check if stack exists
    if aws cloudformation describe-stacks --stack-name "$stack_name" --region "$REGION" &>/dev/null; then
        log_info "Stack exists, updating..."
        aws cloudformation update-stack \
            --stack-name "$stack_name" \
            --template-body "file://$CLOUDFORMATION_FILE" \
            --region "$REGION" \
            --capabilities CAPABILITY_IAM || {
            log_warning "No updates to perform or update failed"
        }
    else
        log_info "Creating new stack..."
        aws cloudformation create-stack \
            --stack-name "$stack_name" \
            --template-body "file://$CLOUDFORMATION_FILE" \
            --region "$REGION" \
            --capabilities CAPABILITY_IAM
    fi
    
    log_info "Waiting for stack operation to complete..."
    aws cloudformation wait stack-create-complete --stack-name "$stack_name" --region "$REGION" 2>/dev/null || \
    aws cloudformation wait stack-update-complete --stack-name "$stack_name" --region "$REGION" 2>/dev/null || {
        log_error "Stack operation failed or timed out"
        return 1
    }
    
    log_success "CloudFormation stack deployed successfully"
    
    # Show outputs
    log_info "Stack outputs:"
    aws cloudformation describe-stacks --stack-name "$stack_name" --region "$REGION" \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' --output table
}

validate_files() {
    log_info "Validating JSON files..."
    
    validate_json "$BUCKET_POLICY_FILE" "Bucket Policy" || exit 1
    validate_json "$OBJECT_POLICY_FILE" "Object Policy" || exit 1
    validate_json "$CLOUDFORMATION_FILE" "CloudFormation Template" || exit 1
    
    # Validate CloudFormation template
    log_info "Validating CloudFormation template..."
    if aws cloudformation validate-template --template-body "file://$CLOUDFORMATION_FILE" --region "$REGION" > /dev/null; then
        log_success "CloudFormation template is valid"
    else
        log_error "CloudFormation template validation failed"
        exit 1
    fi
}

cleanup_resources() {
    local bucket_name="$1"
    local stack_name="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would cleanup resources"
        return 0
    fi
    
    # Remove bucket policy
    if [[ -n "$bucket_name" ]]; then
        log_info "Removing bucket policy from $bucket_name..."
        aws s3api delete-bucket-policy --bucket "$bucket_name" --region "$REGION" 2>/dev/null || \
            log_warning "Failed to remove bucket policy (may not exist)"
    fi
    
    # Delete CloudFormation stack
    if [[ -n "$stack_name" ]]; then
        log_info "Deleting CloudFormation stack: $stack_name..."
        aws cloudformation delete-stack --stack-name "$stack_name" --region "$REGION"
        
        log_info "Waiting for stack deletion to complete..."
        aws cloudformation wait stack-delete-complete --stack-name "$stack_name" --region "$REGION"
        log_success "Stack deleted successfully"
    fi
}

# Parse command line arguments
COMMAND=""
while [[ $# -gt 0 ]]; do
    case $1 in
        deploy-policy|deploy-cf|deploy-all|validate|cleanup)
            COMMAND="$1"
            shift
            ;;
        -b|--bucket-name)
            BUCKET_NAME="$2"
            shift 2
            ;;
        -s|--stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -p|--policy-type)
            POLICY_TYPE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    log_info "Starting AWS S3 deployment script..."
    
    if [[ "$VERBOSE" == "true" ]]; then
        set -x
    fi
    
    check_aws_cli
    check_files
    
    case "$COMMAND" in
        deploy-policy)
            if [[ -z "$BUCKET_NAME" ]]; then
                log_error "Bucket name is required for policy deployment"
                exit 1
            fi
            
            case "$POLICY_TYPE" in
                bucket)
                    deploy_bucket_policy "$BUCKET_NAME" "$BUCKET_POLICY_FILE"
                    ;;
                object)
                    deploy_bucket_policy "$BUCKET_NAME" "$OBJECT_POLICY_FILE"
                    ;;
                both)
                    deploy_bucket_policy "$BUCKET_NAME" "$BUCKET_POLICY_FILE"
                    deploy_bucket_policy "$BUCKET_NAME" "$OBJECT_POLICY_FILE"
                    ;;
                *)
                    log_error "Invalid policy type: $POLICY_TYPE"
                    exit 1
                    ;;
            esac
            ;;
        deploy-cf)
            if [[ -z "$STACK_NAME" ]]; then
                log_error "Stack name is required for CloudFormation deployment"
                exit 1
            fi
            deploy_cloudformation "$STACK_NAME"
            ;;
        deploy-all)
            if [[ -z "$BUCKET_NAME" || -z "$STACK_NAME" ]]; then
                log_error "Both bucket name and stack name are required"
                exit 1
            fi
            deploy_cloudformation "$STACK_NAME"
            deploy_bucket_policy "$BUCKET_NAME" "$BUCKET_POLICY_FILE"
            ;;
        validate)
            validate_files
            ;;
        cleanup)
            cleanup_resources "$BUCKET_NAME" "$STACK_NAME"
            ;;
        ""|*)
            log_error "No command specified or invalid command"
            show_help
            exit 1
            ;;
    esac
    
    log_success "Script completed successfully!"
}

# Run main function
main
