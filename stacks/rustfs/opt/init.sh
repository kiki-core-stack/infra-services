#!/bin/sh

# For each environment in RUSTFS_INIT_ENVIRONMENTS, creates the buckets <PROJECT_NAME>-<environment>-public and -private
# and the user <PROJECT_NAME>-<environment> allowed to use only them. Existing buckets and users are kept, so reruns never
# rotate a secret key; it is written to <output>/<PROJECT_NAME>-<environment>.env only when the user is created.

set -eu

# Constants/Variables
readonly ALIAS='rustfs'
TEMP_DIR=''

# Functions

# The rc image cannot load the shared log library, so these mirror its output.
log_error() {
    printf '[rustfs-init] ERROR: %s\n' "$*" >&2
}

log_info() {
    printf '[rustfs-init] INFO: %s\n' "$*"
}

log_success() {
    printf '[rustfs-init] SUCCESS: %s\n' "$*"
}

cleanup() {
    if [ -n "${TEMP_DIR}" ]; then rm -rf -- "${TEMP_DIR}"; fi
}

generate_secret_key() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40
}

uri_encode() {
    jq -nr --arg value "$1" '$value | @uri'
}

ensure_buckets() {
    prefix="$1"
    for visibility in public private; do
        log_info "Ensuring bucket: ${prefix}-${visibility}..."
        rc --quiet mb --ignore-existing "${ALIAS}/${prefix}-${visibility}"
    done

    # Anonymous reads of files/* only (served through the gateway); replaces the whole bucket policy.
    cat >"${TEMP_DIR}/public-bucket-policy.json" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": { "AWS": ["*"] },
            "Action": ["s3:GetObject"],
            "Resource": ["arn:aws:s3:::${prefix}-public/files/*"]
        }
    ]
}
EOF
    rc --quiet anonymous set-json "${TEMP_DIR}/public-bucket-policy.json" "${ALIAS}/${prefix}-public"
}

ensure_user() {
    prefix="$1"
    cat >"${TEMP_DIR}/user-policy.json" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:DeleteObject",
                "s3:GetBucketLocation",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::${prefix}-private",
                "arn:aws:s3:::${prefix}-private/*",
                "arn:aws:s3:::${prefix}-public",
                "arn:aws:s3:::${prefix}-public/*"
            ]
        }
    ]
}
EOF
    log_info "Ensuring policy: ${prefix}-files..."
    rc --quiet admin policy create "${ALIAS}" "${prefix}-files" "${TEMP_DIR}/user-policy.json"

    set +e
    rc --quiet admin user info "${ALIAS}" "${prefix}" >/dev/null 2>&1
    user_info_exit_code=$?
    set -e

    case "${user_info_exit_code}" in
    0) log_info "User exists; keeping its secret key: ${prefix}" ;;
    5)
        log_info "Creating user: ${prefix}..."
        # `user add` only takes the secret key as an argument, so it gets a throwaway key that is replaced right
        # away through a file.
        rc --quiet admin user add "${ALIAS}" "${prefix}" "$(generate_secret_key)"
        secret_key="$(generate_secret_key)"
        printf '%s' "${secret_key}" >"${TEMP_DIR}/secret-key"
        rc --quiet admin user passwd "${ALIAS}" "${prefix}" --password-file "${TEMP_DIR}/secret-key"
        printf "FILE_STORAGE_S3_SECRET_ACCESS_KEY='%s'\n" "${secret_key}" >"/output/${prefix}.env"
        chmod 600 "/output/${prefix}.env"
        log_success "Secret key written to the output directory: ${prefix}.env"
        ;;
    *)
        log_error "Failed to look up user ${prefix}; rc exited with: ${user_info_exit_code}"
        exit 1
        ;;
    esac

    rc --quiet admin policy attach "${ALIAS}" "${prefix}-files" --user "${prefix}"
}

# Run
main() {
    umask 077
    TEMP_DIR="$(mktemp -d)"
    trap cleanup EXIT

    # rc reads the alias from the environment, keeping the root credentials out of argv and the config file.
    root_access_key="$(uri_encode "$(cat /run/secrets/RUSTFS_ACCESS_KEY)")"
    root_secret_key="$(uri_encode "$(cat /run/secrets/RUSTFS_SECRET_KEY)")"
    export "RC_HOST_${ALIAS}=http://${root_access_key}:${root_secret_key}@${RUSTFS_HOST}"

    for environment in $(printf '%s' "${RUSTFS_INIT_ENVIRONMENTS}" | tr ',' ' '); do
        ensure_buckets "${PROJECT_NAME}-${environment}"
        ensure_user "${PROJECT_NAME}-${environment}"
    done

    log_success 'RustFS initialized'
}

main "$@"
