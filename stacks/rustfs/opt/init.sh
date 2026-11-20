#!/bin/sh

# Creates the project's file storage: for each environment in RUSTFS_INIT_ENVIRONMENTS, the buckets
# <PROJECT_NAME>-<environment>-public and -private, then the user <PROJECT_NAME> allowed to use them. Existing buckets
# and the existing user are kept, so reruns never rotate the user's secret key; it is written to the output directory
# only when the user is created.

set -eu

# Constants/Variables
readonly ALIAS='rustfs'
readonly CREDENTIALS_PATH='/output/credentials.env'
readonly USER_NAME="${PROJECT_NAME}"
readonly USER_POLICY="${PROJECT_NAME}-files"
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
    bucket_resources=''
    for environment in $(printf '%s' "${RUSTFS_INIT_ENVIRONMENTS}" | tr ',' ' '); do
        for visibility in public private; do
            bucket="${PROJECT_NAME}-${environment}-${visibility}"
            log_info "Ensuring bucket: ${bucket}..."
            rc --quiet mb --ignore-existing "${ALIAS}/${bucket}"
            bucket_resources="${bucket_resources}\"arn:aws:s3:::${bucket}\",\"arn:aws:s3:::${bucket}/*\","
        done

        # Anonymous reads of files/* only (served through the gateway); replaces the whole bucket policy.
        public_bucket="${PROJECT_NAME}-${environment}-public"
        cat >"${TEMP_DIR}/public-bucket-policy.json" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": { "AWS": ["*"] },
            "Action": ["s3:GetObject"],
            "Resource": ["arn:aws:s3:::${public_bucket}/files/*"]
        }
    ]
}
EOF
        rc --quiet anonymous set-json "${TEMP_DIR}/public-bucket-policy.json" "${ALIAS}/${public_bucket}"
    done

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
            "Resource": [${bucket_resources%,}]
        }
    ]
}
EOF
}

ensure_user() {
    log_info "Ensuring policy: ${USER_POLICY}..."
    rc --quiet admin policy create "${ALIAS}" "${USER_POLICY}" "${TEMP_DIR}/user-policy.json"

    set +e
    rc --quiet admin user info "${ALIAS}" "${USER_NAME}" >/dev/null 2>&1
    user_info_exit_code=$?
    set -e

    case "${user_info_exit_code}" in
    0) log_info "User exists; keeping its secret key: ${USER_NAME}" ;;
    5)
        log_info "Creating user: ${USER_NAME}..."
        # `user add` only takes the secret key as an argument, so it gets a throwaway key that is replaced right
        # away through a file.
        rc --quiet admin user add "${ALIAS}" "${USER_NAME}" "$(generate_secret_key)"
        secret_key="$(generate_secret_key)"
        printf '%s' "${secret_key}" >"${TEMP_DIR}/secret-key"
        rc --quiet admin user passwd "${ALIAS}" "${USER_NAME}" --password-file "${TEMP_DIR}/secret-key"
        printf "FILE_STORAGE_S3_ACCESS_KEY_ID='%s'\nFILE_STORAGE_S3_SECRET_ACCESS_KEY='%s'\n" \
            "${USER_NAME}" \
            "${secret_key}" >"${CREDENTIALS_PATH}"
        chmod 600 "${CREDENTIALS_PATH}"
        log_success "User credentials written to the output directory: credentials.env"
        ;;
    *)
        log_error "Failed to look up user ${USER_NAME}; rc exited with: ${user_info_exit_code}"
        exit 1
        ;;
    esac

    rc --quiet admin policy attach "${ALIAS}" "${USER_POLICY}" --user "${USER_NAME}"
}

# Run
main() {
    umask 077
    TEMP_DIR="$(mktemp -d)"
    trap cleanup EXIT

    # rc reads the alias from the environment, keeping the root credentials out of argv and the config file.
    access_key="$(uri_encode "$(cat /run/secrets/RUSTFS_ACCESS_KEY)")"
    secret_key="$(uri_encode "$(cat /run/secrets/RUSTFS_SECRET_KEY)")"
    export "RC_HOST_${ALIAS}=http://${access_key}:${secret_key}@${RUSTFS_HOST}"

    ensure_buckets
    ensure_user
    log_success 'RustFS initialized'
}

main "$@"
