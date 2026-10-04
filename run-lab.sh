#!/bin/sh
set -eu

LAB_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LAB_SUFFIX=$$
BUILDER="buildkit-imds-lab-$LAB_SUFFIX"
MOCK="buildkit-imds-mock-$LAB_SUFFIX"
MOCK_IMAGE="buildkit-imds-mock:local"
LAB_TMP=$(mktemp -d "${TMPDIR:-/tmp}/buildkit-imds-lab.XXXXXX")
DEFAULT_LOG="$LAB_TMP/default.log"
NONE_LOG="$LAB_TMP/none.log"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    ESC=$(printf '\033')
    BOLD_CYAN="${ESC}[1;36m"
    GREEN="${ESC}[32m"
    YELLOW="${ESC}[33m"
    RED="${ESC}[31m"
    RESET="${ESC}[0m"
else
    BOLD_CYAN=""
    GREEN=""
    YELLOW=""
    RED=""
    RESET=""
fi

heading() {
    printf '\n%s=== %s ===%s\n' "$BOLD_CYAN" "$1" "$RESET"
}

render_log() {
    if [ -n "$GREEN" ]; then
        sed \
            -e "s/RESULT reachable/${GREEN}&${RESET}/g" \
            -e "s/RESULT unreachable/${YELLOW}&${RESET}/g" \
            "$1"
    else
        cat "$1"
    fi
}

cleanup() {
    docker exec "$MOCK" ip address del 169.254.169.254/32 dev lo >/dev/null 2>&1 || true
    docker rm -f "$MOCK" >/dev/null 2>&1 || true
    docker buildx rm "$BUILDER" >/dev/null 2>&1 || true
    rm -rf "$LAB_TMP"
}
trap cleanup EXIT INT TERM

docker build -f "$LAB_DIR/Dockerfile.mock" -t "$MOCK_IMAGE" "$LAB_DIR"

docker run -d \
    --name "$MOCK" \
    --network host \
    --cap-add NET_ADMIN \
    --entrypoint sh \
    "$MOCK_IMAGE" \
    -c 'ip address add 169.254.169.254/32 dev lo && exec python /lab/mock_imds.py' \
    >/dev/null

docker buildx create \
    --name "$BUILDER" \
    --driver docker-container \
    --use \
    >/dev/null
docker buildx inspect --bootstrap "$BUILDER" >/dev/null

heading 'default RUN network (test)'
if ! docker buildx build \
    --builder "$BUILDER" \
    --file "$LAB_DIR/Dockerfile.probe" \
    --no-cache \
    --progress plain \
    "$LAB_DIR" >"$DEFAULT_LOG" 2>&1; then
    render_log "$DEFAULT_LOG"
    printf '%sERROR: default-network build failed%s\n' "$RED" "$RESET"
    exit 1
fi
render_log "$DEFAULT_LOG"
grep -q 'RESULT reachable transport=.* role=lab-role access_key=LAB_CANARY_NOT_A_SECRET' "$DEFAULT_LOG"

heading 'network=none (negative control)'
if ! docker buildx build \
    --builder "$BUILDER" \
    --file "$LAB_DIR/Dockerfile.probe" \
    --network none \
    --no-cache \
    --progress plain \
    "$LAB_DIR" >"$NONE_LOG" 2>&1; then
    render_log "$NONE_LOG"
    printf '%sERROR: network=none build failed%s\n' "$RED" "$RESET"
    exit 1
fi
render_log "$NONE_LOG"
grep -q 'RESULT unreachable' "$NONE_LOG"

heading 'fake IMDS request log'
docker logs "$MOCK"

printf '\n%sVERDICT: REACHABLE%s — default BuildKit RUN network reached fake IMDS; network=none did not.\n' "$RED" "$RESET"
