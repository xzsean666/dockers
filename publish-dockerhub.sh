#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

IMAGE="${RCLONE_SYNC_IMAGE:-${DOCKER_IMAGE:-}}"
TAG="${RCLONE_SYNC_TAG:-}"
PLATFORMS="${RCLONE_SYNC_PLATFORMS:-linux/amd64,linux/arm64}"
CONTEXT="${DOCKER_BUILD_CONTEXT:-${PUBLISH_CONTEXT:-.}}"
DOCKERFILE="${DOCKERFILE:-Dockerfile}"
RCLONE_IMAGE="${RCLONE_IMAGE:-}"
BUILD_ARGS=()
PUSH=1
LOAD=0
LATEST=1
RUN_TESTS=1
DRY_RUN=0
BUILDER="${PUBLISH_BUILDER:-${RCLONE_SYNC_BUILDER:-}}"
BUILDER_EXPLICIT=0
if [[ -n "$BUILDER" ]]; then
    BUILDER_EXPLICIT=1
fi
DEFAULT_MULTI_PLATFORM_BUILDER="${PUBLISH_DEFAULT_BUILDER:-dockers-publisher}"
INSTALL_BINFMT="${PUBLISH_INSTALL_BINFMT:-0}"
BINFMT_IMAGE="${PUBLISH_BINFMT_IMAGE:-tonistiigi/binfmt:latest}"
BINFMT_RETRIES="${PUBLISH_BINFMT_RETRIES:-3}"
UPDATE_README="${PUBLISH_UPDATE_README:-1}"
README_FILE="${PUBLISH_README_FILE:-README.md}"
README_EXPLICIT=0
if [[ -n "${PUBLISH_README_FILE:-}" ]]; then
    README_EXPLICIT=1
fi
HUB_DESCRIPTION="${PUBLISH_DESCRIPTION:-}"

usage() {
    cat <<'EOF'
Usage:
  ./publish-dockerhub.sh --context <dir> --file <Dockerfile> --image <dockerhub-user/image> --tag <tag> [options]

Examples:
  ./publish-dockerhub.sh --context rclone-sync --image seanxyz/rclone-sync --tag 0.1.0

  DOCKERHUB_USERNAME=seanxyz DOCKERHUB_TOKEN=xxxxx \
    ./publish-dockerhub.sh --context rclone-sync --image seanxyz/rclone-sync --tag 0.1.0

  ./publish-dockerhub.sh \
    --context rclone-sync \
    --file Dockerfile \
    --image seanxyz/rclone-sync \
    --tag 0.1.0 \
    --platforms linux/amd64,linux/arm64 \
    --no-latest

Options:
  -c, --context DIR       Docker build context. Default: current repo root.
  -f, --file FILE         Dockerfile path. Relative paths are resolved from context. Default: Dockerfile.
  -i, --image IMAGE        Docker Hub image, for example username/rclone-sync.
  -t, --tag TAG            Version tag to publish, for example 0.1.0.
  -p, --platforms LIST     Build platforms. Default: linux/amd64,linux/arm64.
      --rclone-image IMG   Override Dockerfile base image build arg.
      --build-arg ARG      Pass one Docker build arg, for example KEY=VALUE. Can repeat.
      --builder NAME       buildx builder name. For multi-platform push, the
                           script auto-creates/uses dockers-publisher when omitted.
      --install-binfmt     Install binfmt/QEMU through tonistiigi/binfmt if the
                           builder does not report a requested platform.
      --binfmt-image IMG   binfmt installer image. Default: tonistiigi/binfmt:latest.
      --readme FILE        Update Docker Hub overview from this Markdown file.
                           Relative paths are resolved from context. Default: README.md.
      --no-readme          Do not update Docker Hub overview after push.
      --description TEXT   Docker Hub short description. Maximum 100 characters.
      --no-latest          Do not also tag/push IMAGE:latest.
      --skip-tests         Skip Python compile and local smoke tests.
      --load               Build for local Docker only instead of pushing.
      --dry-run            Print commands without running them.
  -h, --help               Show this help.

Environment:
  RCLONE_SYNC_IMAGE        Same as --image.
  RCLONE_SYNC_TAG          Same as --tag.
  RCLONE_SYNC_PLATFORMS    Same as --platforms.
  PUBLISH_CONTEXT          Same as --context.
  DOCKERFILE               Same as --file.
  DOCKERHUB_USERNAME       Optional docker login username.
  DOCKERHUB_TOKEN          Optional docker login token/password.
  PUBLISH_BUILDER          Optional buildx builder name.
  PUBLISH_DEFAULT_BUILDER  Auto builder name for multi-platform push. Default: dockers-publisher.
  PUBLISH_INSTALL_BINFMT   Set to 1 to install binfmt/QEMU when needed.
  PUBLISH_BINFMT_IMAGE     binfmt installer image. Default: tonistiigi/binfmt:latest.
  PUBLISH_BINFMT_RETRIES   binfmt installer retry count. Default: 3.
  PUBLISH_UPDATE_README    Set to 0 to skip Docker Hub overview update. Default: 1.
  PUBLISH_README_FILE      Markdown file for Docker Hub overview. Default: README.md.
  PUBLISH_DESCRIPTION      Optional Docker Hub short description, max 100 characters.

Notes:
  - This script never stores Docker Hub credentials.
  - If DOCKERHUB_USERNAME and DOCKERHUB_TOKEN are not set, it assumes you
    already ran `docker login`.
  - --load only supports a single platform because Docker cannot load a
    multi-platform build into the local image store.
EOF
}

log() {
    printf '[publish] %s\n' "$*"
}

die() {
    printf '[publish] ERROR: %s\n' "$*" >&2
    exit 1
}

run() {
    log "+ $*"
    if [[ "$DRY_RUN" == "0" ]]; then
        "$@"
    fi
}

dockerhub_auth_token() {
    local auth_payload auth_response token

    auth_payload="$(
        DOCKERHUB_USERNAME="$DOCKERHUB_USERNAME" DOCKERHUB_TOKEN="$DOCKERHUB_TOKEN" python3 - <<'PY'
import json
import os

print(json.dumps({
    "username": os.environ["DOCKERHUB_USERNAME"],
    "password": os.environ["DOCKERHUB_TOKEN"],
}))
PY
    )"

    auth_response="$(
        printf '%s' "$auth_payload" \
            | curl -fsS \
                -H "Content-Type: application/json" \
                --data-binary @- \
                "https://hub.docker.com/v2/users/login/"
    )" || die "Docker Hub API login failed"

    token="$(
        printf '%s' "$auth_response" | python3 -c '
import json
import sys

print(json.load(sys.stdin).get("token", ""))
'
    )"
    [[ -n "$token" ]] || die "Docker Hub API login response did not include token"
    printf '%s' "$token"
}

update_dockerhub_overview() {
    [[ "$PUSH" == "1" ]] || return 0
    [[ "$UPDATE_README" == "1" ]] || return 0

    local readme_path namespace repository payload token
    if [[ "$README_FILE" = /* ]]; then
        readme_path="$README_FILE"
    else
        readme_path="$CONTEXT_DIR/$README_FILE"
    fi

    if [[ ! -f "$readme_path" ]]; then
        if [[ "$README_EXPLICIT" == "1" ]]; then
            die "README file not found: $readme_path"
        fi
        log "No README file found at $readme_path; skipping Docker Hub overview update"
        return 0
    fi

    if [[ -z "${DOCKERHUB_USERNAME:-}" || -z "${DOCKERHUB_TOKEN:-}" ]]; then
        if [[ "$README_EXPLICIT" == "1" ]]; then
            die "DOCKERHUB_USERNAME and DOCKERHUB_TOKEN are required to update Docker Hub overview"
        fi
        log "Skipping Docker Hub overview update; set DOCKERHUB_USERNAME/DOCKERHUB_TOKEN to publish $README_FILE"
        return 0
    fi

    if [[ "$IMAGE" != */* || "$IMAGE" == */*/* ]]; then
        if [[ "$README_EXPLICIT" == "1" ]]; then
            die "Docker Hub overview update requires image format namespace/repository: $IMAGE"
        fi
        log "Skipping Docker Hub overview update; image is not in namespace/repository form: $IMAGE"
        return 0
    fi
    command -v curl >/dev/null 2>&1 || die "curl is required to update Docker Hub overview"
    command -v python3 >/dev/null 2>&1 || die "python3 is required to update Docker Hub overview"

    namespace="${IMAGE%%/*}"
    repository="${IMAGE#*/}"

    if [[ "$DRY_RUN" == "1" ]]; then
        log "+ update Docker Hub overview for $namespace/$repository from $readme_path"
        return 0
    fi

    log "Updating Docker Hub overview for $namespace/$repository from $readme_path"
    token="$(dockerhub_auth_token)"
    payload="$(
        README_PATH="$readme_path" HUB_DESCRIPTION="$HUB_DESCRIPTION" python3 - <<'PY'
import json
import os
from pathlib import Path

payload = {
    "full_description": Path(os.environ["README_PATH"]).read_text(encoding="utf-8"),
}
description = os.environ.get("HUB_DESCRIPTION", "")
if description:
    payload["description"] = description
print(json.dumps(payload, ensure_ascii=False))
PY
    )"

    printf '%s' "$payload" \
        | curl -fsS \
            -X PATCH \
            -H "Authorization: JWT $token" \
            -H "Content-Type: application/json" \
            --data-binary @- \
            "https://hub.docker.com/v2/repositories/$namespace/$repository/" \
            >/dev/null \
        || die "failed to update Docker Hub overview for $namespace/$repository"

    log "Updated Docker Hub overview for $namespace/$repository"
}

buildx_driver() {
    docker buildx inspect "$1" 2>/dev/null | awk -F': *' '/^Driver:/ {print $2; exit}'
}

missing_buildx_platforms() {
    local available
    available="$(docker buildx inspect "$BUILDER" 2>/dev/null | awk -F': *' '/^Platforms:/ {print $2; exit}')"
    available="${available// /}"
    [[ -n "$available" ]] || return 0

    local missing=()
    local requested_platform
    IFS=',' read -ra requested_platforms <<< "$PLATFORMS"
    for requested_platform in "${requested_platforms[@]}"; do
        requested_platform="${requested_platform// /}"
        [[ -n "$requested_platform" ]] || continue
        if [[ ",$available," != *",$requested_platform,"* ]]; then
            missing+=("$requested_platform")
        fi
    done

    printf '%s\n' "${missing[*]}"
}

install_binfmt() {
    local attempt=1
    while (( attempt <= BINFMT_RETRIES )); do
        log "+ docker run --privileged --rm $BINFMT_IMAGE --install all"
        if docker run --privileged --rm "$BINFMT_IMAGE" --install all; then
            return 0
        fi
        if (( attempt == BINFMT_RETRIES )); then
            return 1
        fi
        log "binfmt install failed; retrying ($attempt/$BINFMT_RETRIES)"
        sleep $((attempt * 5))
        attempt=$((attempt + 1))
    done
}

check_requested_platforms() {
    [[ "$PUSH" == "1" ]] || return 0
    [[ "$PLATFORMS" == *,* ]] || return 0

    local missing
    missing="$(missing_buildx_platforms)"
    [[ -n "$missing" ]] || return 0

    if [[ "$INSTALL_BINFMT" == "1" ]]; then
        install_binfmt || die "failed to install binfmt/QEMU with image '$BINFMT_IMAGE'"
        docker buildx inspect "$BUILDER" --bootstrap >/dev/null
        missing="$(missing_buildx_platforms)"
        [[ -z "$missing" ]] || die "builder '$BUILDER' still does not report platform(s): $missing"
        return 0
    fi

    log "WARNING: builder '$BUILDER' does not report platform(s): $missing"
    log "WARNING: buildx will continue; if arm64 build fails, rerun with --install-binfmt or run: docker run --privileged --rm $BINFMT_IMAGE --install all"
}

ensure_multi_platform_builder() {
    [[ "$PUSH" == "1" ]] || return 0
    [[ "$PLATFORMS" == *,* ]] || return 0

    if [[ -z "$BUILDER" ]]; then
        BUILDER="$DEFAULT_MULTI_PLATFORM_BUILDER"
        log "Using buildx builder '$BUILDER' for multi-platform push"
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
        log "+ docker buildx inspect $BUILDER || docker buildx create --name $BUILDER --driver docker-container --use"
        log "+ docker buildx inspect $BUILDER --bootstrap"
        return 0
    fi

    local driver
    driver="$(buildx_driver "$BUILDER" || true)"
    if [[ -z "$driver" ]]; then
        log "Creating buildx builder '$BUILDER' with docker-container driver"
        docker buildx create --name "$BUILDER" --driver docker-container --use >/dev/null
    elif [[ "$driver" == "docker" ]]; then
        if [[ "$BUILDER_EXPLICIT" == "1" ]]; then
            die "builder '$BUILDER' uses docker driver and cannot do multi-platform push; use a docker-container builder or omit --builder"
        fi
        die "auto builder '$BUILDER' already exists with docker driver; remove it or set PUBLISH_DEFAULT_BUILDER to another name"
    else
        log "Using existing buildx builder '$BUILDER' with driver '$driver'"
    fi

    docker buildx inspect "$BUILDER" --bootstrap >/dev/null
    check_requested_platforms
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--context)
            CONTEXT="${2:-}"
            shift 2
            ;;
        -f|--file|--dockerfile)
            DOCKERFILE="${2:-}"
            shift 2
            ;;
        -i|--image)
            IMAGE="${2:-}"
            shift 2
            ;;
        -t|--tag)
            TAG="${2:-}"
            shift 2
            ;;
        -p|--platforms)
            PLATFORMS="${2:-}"
            shift 2
            ;;
        --rclone-image)
            RCLONE_IMAGE="${2:-}"
            shift 2
            ;;
        --build-arg)
            BUILD_ARGS+=("${2:-}")
            shift 2
            ;;
        --builder)
            BUILDER="${2:-}"
            BUILDER_EXPLICIT=1
            shift 2
            ;;
        --install-binfmt)
            INSTALL_BINFMT=1
            shift
            ;;
        --binfmt-image)
            BINFMT_IMAGE="${2:-}"
            shift 2
            ;;
        --readme)
            README_FILE="${2:-}"
            UPDATE_README=1
            README_EXPLICIT=1
            shift 2
            ;;
        --no-readme)
            UPDATE_README=0
            shift
            ;;
        --description)
            HUB_DESCRIPTION="${2:-}"
            shift 2
            ;;
        --no-latest)
            LATEST=0
            shift
            ;;
        --skip-tests|--no-tests)
            RUN_TESTS=0
            shift
            ;;
        --load)
            PUSH=0
            LOAD=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

[[ -n "$IMAGE" ]] || die "--image is required, for example --image username/rclone-sync"
[[ -n "$TAG" ]] || die "--tag is required, for example --tag 0.1.0"
[[ -n "$CONTEXT" ]] || die "--context cannot be empty"
[[ -n "$DOCKERFILE" ]] || die "--file cannot be empty"
[[ -n "$BINFMT_IMAGE" ]] || die "--binfmt-image cannot be empty"
[[ -n "$README_FILE" ]] || die "--readme cannot be empty"
[[ "$IMAGE" =~ ^[a-z0-9][a-z0-9._-]*/[a-z0-9][a-z0-9._/-]*$ ]] || die "invalid Docker image name: $IMAGE"
[[ "$TAG" =~ ^[A-Za-z0-9_.-]+$ ]] || die "invalid tag: $TAG"
[[ "$BINFMT_RETRIES" =~ ^[1-9][0-9]*$ ]] || die "PUBLISH_BINFMT_RETRIES must be a positive integer"
[[ "$UPDATE_README" =~ ^[01]$ ]] || die "PUBLISH_UPDATE_README must be 0 or 1"
(( ${#HUB_DESCRIPTION} <= 100 )) || die "--description/PUBLISH_DESCRIPTION must be 100 characters or less"

if [[ "$CONTEXT" = /* ]]; then
    CONTEXT_DIR="$CONTEXT"
else
    CONTEXT_DIR="$REPO_DIR/$CONTEXT"
fi
CONTEXT_DIR="$(cd -- "$CONTEXT_DIR" && pwd)" || die "build context not found: $CONTEXT"

if [[ "$DOCKERFILE" = /* ]]; then
    DOCKERFILE_PATH="$DOCKERFILE"
else
    DOCKERFILE_PATH="$CONTEXT_DIR/$DOCKERFILE"
fi
[[ -f "$DOCKERFILE_PATH" ]] || die "Dockerfile not found: $DOCKERFILE_PATH"

if [[ "$LOAD" == "1" && "$PLATFORMS" == *,* ]]; then
    die "--load only supports one platform; use --platforms linux/amd64"
fi

command -v docker >/dev/null 2>&1 || die "docker is required"
docker buildx version >/dev/null 2>&1 || die "docker buildx is required"

if [[ "$RUN_TESTS" == "1" ]]; then
    if [[ -f "$CONTEXT_DIR/runner.py" && -f "$CONTEXT_DIR/tools/google-drive-refresh-token.py" ]] && command -v python3 >/dev/null 2>&1; then
        run python3 -m py_compile "$CONTEXT_DIR/runner.py" "$CONTEXT_DIR/tools/google-drive-refresh-token.py"
    elif [[ -f "$CONTEXT_DIR/runner.py" ]] && command -v python3 >/dev/null 2>&1; then
        run python3 -m py_compile "$CONTEXT_DIR/runner.py"
    else
        log "No Python runner compile check for context: $CONTEXT_DIR"
    fi

    if [[ -x "$CONTEXT_DIR/test-local.sh" ]] && command -v rclone >/dev/null 2>&1; then
        run "$CONTEXT_DIR/test-local.sh"
    elif [[ -x "$CONTEXT_DIR/test-local.sh" ]]; then
        log "rclone not found on host; skipping local smoke test"
    else
        log "No local smoke test for context: $CONTEXT_DIR"
    fi
fi

if [[ -n "${DOCKERHUB_USERNAME:-}" && -n "${DOCKERHUB_TOKEN:-}" ]]; then
    log "Logging in to Docker Hub as ${DOCKERHUB_USERNAME}"
    if [[ "$DRY_RUN" == "0" ]]; then
        printf '%s' "$DOCKERHUB_TOKEN" | docker login --username "$DOCKERHUB_USERNAME" --password-stdin
    else
        log "+ docker login --username ${DOCKERHUB_USERNAME} --password-stdin"
    fi
else
    log "DOCKERHUB_USERNAME/DOCKERHUB_TOKEN not set; assuming docker is already logged in"
fi

ensure_multi_platform_builder

build_cmd=(docker buildx build "$CONTEXT_DIR")
build_cmd+=(--file "$DOCKERFILE_PATH")
build_cmd+=(--platform "$PLATFORMS")
build_cmd+=(--tag "$IMAGE:$TAG")
if [[ "$LATEST" == "1" ]]; then
    build_cmd+=(--tag "$IMAGE:latest")
fi
if [[ -n "$RCLONE_IMAGE" ]]; then
    build_cmd+=(--build-arg "RCLONE_IMAGE=$RCLONE_IMAGE")
fi
for build_arg in "${BUILD_ARGS[@]}"; do
    [[ -n "$build_arg" ]] || die "--build-arg value cannot be empty"
    build_cmd+=(--build-arg "$build_arg")
done
if [[ -n "$BUILDER" ]]; then
    build_cmd+=(--builder "$BUILDER")
fi
if [[ "$PUSH" == "1" ]]; then
    build_cmd+=(--push)
else
    build_cmd+=(--load)
fi

run "${build_cmd[@]}"
update_dockerhub_overview

if [[ "$DRY_RUN" == "1" ]]; then
    log "Dry run complete; no image was built, loaded, or pushed"
elif [[ "$PUSH" == "1" ]]; then
    log "Published $IMAGE:$TAG"
    if [[ "$LATEST" == "1" ]]; then
        log "Published $IMAGE:latest"
    fi
else
    log "Loaded $IMAGE:$TAG into local Docker"
fi
