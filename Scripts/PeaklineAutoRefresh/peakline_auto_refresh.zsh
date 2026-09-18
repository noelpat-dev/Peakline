#!/bin/zsh

set -u
set -o pipefail
umask 077

export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

readonly SCRIPT_PATH="${0:A}"
readonly SCRIPT_DIR="${SCRIPT_PATH:h}"
readonly CATALOG_DIR="$SCRIPT_DIR/apps.d"
readonly DEFAULT_APP_KEY="peakline"

APP_KEY="$DEFAULT_APP_KEY"
TARGET_SCOPE="single"
MODE="run"
TARGET_WAS_SET=0
MODE_WAS_SET=0

usage() {
    print "Usage: $SCRIPT_PATH [--app <key>|--all] [--status|--dry-run|--force]"
}

while (( $# > 0 )); do
    case "$1" in
        --status|--dry-run|--force)
            (( MODE_WAS_SET == 0 )) || {
                print -u2 "Choose only one of --status, --dry-run, or --force."
                usage
                exit 64
            }
            MODE="${1#--}"
            MODE_WAS_SET=1
            shift
            ;;
        --app)
            (( $# >= 2 )) || { print -u2 "--app requires a catalog key."; usage; exit 64; }
            (( TARGET_WAS_SET == 0 )) || {
                print -u2 "Choose either --app <key> or --all, not both."
                usage
                exit 64
            }
            APP_KEY="$2"
            TARGET_SCOPE="single"
            TARGET_WAS_SET=1
            shift 2
            ;;
        --all)
            (( TARGET_WAS_SET == 0 )) || {
                print -u2 "Choose either --app <key> or --all, not both."
                usage
                exit 64
            }
            TARGET_SCOPE="all"
            TARGET_WAS_SET=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            print -u2 "Unknown argument: $1"
            usage
            exit 64
            ;;
    esac
done

catalog_keys() {
    local config key
    for config in "$CATALOG_DIR"/*.plist(N); do
        key="${config:t:r}"
        print -r -- "$key"
    done | /usr/bin/sort
}

load_app_config() {
    local field value
    APP_CONFIG="$CATALOG_DIR/$APP_KEY.plist"

    case "$APP_KEY" in
        ""|*[!A-Za-z0-9_-]*)
            print -u2 "Invalid app catalog key: $APP_KEY"
            return 64
            ;;
    esac
    [[ -f "$APP_CONFIG" ]] || {
        print -u2 "App catalog entry not found: $APP_CONFIG"
        return 64
    }
    /usr/bin/plutil -lint "$APP_CONFIG" >/dev/null || {
        print -u2 "Malformed app catalog entry: $APP_CONFIG"
        return 64
    }

    for field in \
        displayName projectRoot projectFile scheme configuration bundleIdentifier \
        teamIdentifier buildDeviceUDID coreDeviceID \
        stateDirectoryName logDirectoryName derivedDataDirectoryName; do
        value="$(/usr/bin/plutil -extract "$field" raw "$APP_CONFIG" 2>/dev/null || true)"
        if [[ -z "$value" || "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
            print -u2 "App catalog entry $APP_CONFIG has no valid string value for $field."
            return 64
        fi
        typeset "$field=$value"
    done

    [[ "$projectRoot" == /* && "$projectFile" != /* ]] || {
        print -u2 "App catalog entry $APP_CONFIG must use an absolute project root and relative project file."
        return 64
    }
    for value in "$stateDirectoryName" "$logDirectoryName" "$derivedDataDirectoryName"; do
        case "$value" in
            "."|".."|*/*)
                print -u2 "App catalog entry $APP_CONFIG has an invalid runtime directory name."
                return 64
                ;;
        esac
    done

    APP_DISPLAY_NAME="$displayName"
    PROJECT_ROOT="$projectRoot"
    if [[ "$APP_KEY" == "$DEFAULT_APP_KEY" && -n "${PEAKLINE_PROJECT_ROOT:-}" ]]; then
        PROJECT_ROOT="$PEAKLINE_PROJECT_ROOT"
    fi
    PROJECT_PATH="$PROJECT_ROOT/$projectFile"
    SCHEME="$scheme"
    CONFIGURATION="$configuration"
    BUNDLE_ID="$bundleIdentifier"
    TEAM_ID="$teamIdentifier"
    BUILD_DEVICE_UDID="$buildDeviceUDID"
    CORE_DEVICE_ID="$coreDeviceID"

    if [[ "$APP_KEY" == "$DEFAULT_APP_KEY" ]]; then
        REFRESH_THRESHOLD_SECONDS="${AUTO_REFRESH_THRESHOLD_SECONDS:-${PEAKLINE_REFRESH_THRESHOLD_SECONDS:-86400}}"
        DEVICE_PREFLIGHT_ATTEMPTS="${AUTO_REFRESH_DEVICE_PREFLIGHT_ATTEMPTS:-${PEAKLINE_DEVICE_PREFLIGHT_ATTEMPTS:-3}}"
        DEVICE_PREFLIGHT_RETRY_DELAY_SECONDS="${AUTO_REFRESH_DEVICE_PREFLIGHT_RETRY_DELAY_SECONDS:-${PEAKLINE_DEVICE_PREFLIGHT_RETRY_DELAY_SECONDS:-5}}"
    else
        REFRESH_THRESHOLD_SECONDS="${AUTO_REFRESH_THRESHOLD_SECONDS:-86400}"
        DEVICE_PREFLIGHT_ATTEMPTS="${AUTO_REFRESH_DEVICE_PREFLIGHT_ATTEMPTS:-3}"
        DEVICE_PREFLIGHT_RETRY_DELAY_SECONDS="${AUTO_REFRESH_DEVICE_PREFLIGHT_RETRY_DELAY_SECONDS:-5}"
    fi

    # These names intentionally retain Peakline's original paths while giving
    # every catalog entry an isolated state, log, and DerivedData namespace.
    STATE_DIR="$HOME/Library/Application Support/$stateDirectoryName"
    LOG_DIR="$HOME/Library/Logs/$logDirectoryName"
    DERIVED_DATA_DIR="$HOME/Library/Developer/Xcode/DerivedData/$derivedDataDirectoryName"
    STATE_PLIST="$STATE_DIR/state.plist"
    LOCK_FILE="$STATE_DIR/run.lock"
    PROFILE_BACKUP_DIR="$STATE_DIR/profile-backups"
    LAST_RESULT_PLIST="$STATE_DIR/last-result.plist"
    BUILD_LOG="$LOG_DIR/xcodebuild.log"
    DEVICE_LOG="$LOG_DIR/devicectl.log"
    NOTIFICATION_STAMP="$STATE_DIR/last-attention-notification-epoch"
    DEVICE_APPS_JSON="$STATE_DIR/device-apps.json"
    DEVICE_PROCESSES_JSON="$STATE_DIR/device-processes.json"
    DECODED_PROFILE="$STATE_DIR/decoded-profile.plist"
    PRODUCT_DIR="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION-iphoneos"
}

run_all() {
    local key child_status aggregate_status=0
    local -a keys child_args
    keys=("${(@f)$(catalog_keys)}")
    (( ${#keys} > 0 )) || {
        print -u2 "No app catalog entries found in $CATALOG_DIR."
        return 64
    }

    # Validate every entry through the read-only path before any selected app
    # can build, quarantine a profile, or contact the device.
    for key in "${keys[@]}"; do
        if ! /bin/zsh "$SCRIPT_PATH" --app "$key" --dry-run >/dev/null; then
            print -u2 "Invalid app catalog entry: $CATALOG_DIR/$key.plist"
            return 64
        fi
    done

    for key in "${keys[@]}"; do
        child_args=(--app "$key")
        [[ "$MODE" == "run" ]] || child_args+=("--$MODE")
        print "=== $key ==="
        /bin/zsh "$SCRIPT_PATH" "${child_args[@]}"
        child_status=$?
        if (( child_status != 0 )); then
            aggregate_status=1
            print -u2 "$key refresh check failed with status $child_status; continuing to the next app."
        fi
    done
    return "$aggregate_status"
}

if [[ "$TARGET_SCOPE" == "all" ]]; then
    run_all
    exit $?
fi

load_app_config || exit $?

# This is deliberately a read-only health check. Xcode remains responsible for
# account authentication, certificates, profiles, and any user-controlled
# prompts needed by automatic signing.
SIGNING_READINESS_AVAILABLE=0
SIGNING_IDENTITY_COUNT=0

[[ "$REFRESH_THRESHOLD_SECONDS" == <-> ]] || {
    print -u2 "Refresh threshold must be a non-negative integer."
    exit 64
}

[[ "$DEVICE_PREFLIGHT_ATTEMPTS" == <-> && "$DEVICE_PREFLIGHT_ATTEMPTS" -ge 1 ]] || {
    print -u2 "Device preflight attempts must be a positive integer."
    exit 64
}

[[ "$DEVICE_PREFLIGHT_RETRY_DELAY_SECONDS" == <-> ]] || {
    print -u2 "Device preflight retry delay must be a non-negative integer."
    exit 64
}

timestamp() {
    /bin/date -u '+%Y-%m-%dT%H:%M:%SZ'
}

log() {
    print -r -- "$(timestamp) $*"
}

record_result() {
    local outcome="$1"
    local message="$2"
    local result_tmp

    [[ -d "$STATE_DIR" ]] || return 0
    result_tmp="$(/usr/bin/mktemp "$STATE_DIR/last-result.plist.XXXXXX" 2>/dev/null)" || return 0
    if ! {
        /usr/bin/plutil -create xml1 "$result_tmp" &&
        /usr/bin/plutil -insert lastAttemptUTC -string "$(timestamp)" "$result_tmp" &&
        /usr/bin/plutil -insert outcome -string "$outcome" "$result_tmp" &&
        /usr/bin/plutil -insert message -string "$message" "$result_tmp" &&
        /usr/bin/plutil -lint "$result_tmp" >/dev/null
    }; then
        /bin/rm -f "$result_tmp"
        return 0
    fi

    /bin/mv -f "$result_tmp" "$LAST_RESULT_PLIST" || /bin/rm -f "$result_tmp"
}

set_attempt_result() {
    ATTEMPT_OUTCOME="$1"
    ATTEMPT_MESSAGE="$2"
}

finish_attempt() {
    set_attempt_result "$1" "$2"
    exit "$3"
}

notify_attention() {
    local message="$1"
    local now last=0
    now="$(/bin/date -u '+%s')"
    [[ -f "$NOTIFICATION_STAMP" ]] && last="$(<"$NOTIFICATION_STAMP")"
    [[ "$last" == <-> ]] || last=0
    (( now - last >= 21600 )) || return 0

    /usr/bin/osascript \
        -e 'on run argv' \
        -e 'display notification (item 1 of argv) with title (item 2 of argv)' \
        -e 'end run' \
        "$message" "$APP_DISPLAY_NAME Auto Refresh" >/dev/null 2>&1 && print -r -- "$now" > "$NOTIFICATION_STAMP"
}

iso_to_epoch() {
    /bin/date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" '+%s' 2>/dev/null
}

current_git_commit() {
    local git_metadata="$PROJECT_ROOT/.git"
    local git_dir="$git_metadata"
    local head_value ref_path commit="unknown"

    if [[ -f "$git_metadata" ]]; then
        git_dir="$(/usr/bin/sed -n 's/^gitdir: //p' "$git_metadata" | /usr/bin/head -n 1)"
        [[ "$git_dir" == /* ]] || git_dir="$PROJECT_ROOT/$git_dir"
    fi

    if [[ -f "$git_dir/HEAD" ]]; then
        head_value="$(<"$git_dir/HEAD")"
        if [[ "$head_value" == 'ref: '* ]]; then
            ref_path="$git_dir/${head_value#ref: }"
            [[ -f "$ref_path" ]] && commit="$(<"$ref_path")"
        elif (( ${#head_value} >= 40 && ${#head_value} <= 64 )) && \
             [[ "$head_value" != *[!0-9A-Fa-f]* ]]; then
            commit="$head_value"
        fi
    fi

    if (( ${#commit} < 40 || ${#commit} > 64 )) || \
       [[ "$commit" == *[!0-9A-Fa-f]* ]]; then
        commit="unknown"
    fi
    print -r -- "$commit"
}

state_expiration() {
    [[ -f "$STATE_PLIST" ]] || return 1
    /usr/bin/plutil -extract profileExpirationUTC raw "$STATE_PLIST" 2>/dev/null
}

compute_signing_readiness() {
    local identity_output valid_identity_count
    identity_output="$(/usr/bin/security find-identity -v -p codesigning 2>&1 || true)"
    valid_identity_count="$(print -r -- "$identity_output" | /usr/bin/awk '/valid identities found/ { print $1; exit }')"

    if [[ "$valid_identity_count" == <-> ]] && (( valid_identity_count > 0 )); then
        SIGNING_READINESS_AVAILABLE=1
        SIGNING_IDENTITY_COUNT="$valid_identity_count"
    else
        SIGNING_READINESS_AVAILABLE=0
        SIGNING_IDENTITY_COUNT=0
    fi
}

show_signing_readiness() {
    compute_signing_readiness
    if (( SIGNING_READINESS_AVAILABLE == 1 )); then
        print "Signing readiness: available ($SIGNING_IDENTITY_COUNT valid code-signing identities found)."
    else
        print "Signing readiness: BLOCKED — no valid code-signing identity found. Configure an Apple ID/signing identity in Xcode; automatic signing may create one after that."
    fi
}

show_status() {
    print "$APP_DISPLAY_NAME Auto Refresh ($APP_KEY)"
    print "State directory: $STATE_DIR"
    print "Log directory: $LOG_DIR"
    print "DerivedData directory: $DERIVED_DATA_DIR"
    if [[ ! -f "$LAST_RESULT_PLIST" ]]; then
        print "Last attempt: none recorded."
    else
        local attempt_timestamp attempt_outcome attempt_message
        attempt_timestamp="$(/usr/bin/plutil -extract lastAttemptUTC raw "$LAST_RESULT_PLIST" 2>/dev/null || true)"
        attempt_outcome="$(/usr/bin/plutil -extract outcome raw "$LAST_RESULT_PLIST" 2>/dev/null || true)"
        attempt_message="$(/usr/bin/plutil -extract message raw "$LAST_RESULT_PLIST" 2>/dev/null || true)"
        if [[ -n "$attempt_timestamp" && -n "$attempt_outcome" && -n "$attempt_message" ]]; then
            print "Last attempt UTC: $attempt_timestamp"
            print "Last attempt outcome: $attempt_outcome"
            print "Last attempt message: $attempt_message"
        else
            print "Last attempt result is unreadable; the next check will record a fresh result."
        fi
    fi

    show_signing_readiness

    if [[ ! -f "$STATE_PLIST" ]]; then
        print "$APP_DISPLAY_NAME Auto Refresh has no recorded successful installation yet."
        return 0
    fi

    local expiration now_epoch expiration_epoch seconds_left
    expiration="$(state_expiration)" || {
        print "$APP_DISPLAY_NAME Auto Refresh state is unreadable; the next check will refresh conservatively."
        return 0
    }
    now_epoch="$(/bin/date -u '+%s')"
    expiration_epoch="$(iso_to_epoch "$expiration")" || {
        print "$APP_DISPLAY_NAME Auto Refresh recorded an invalid expiration; the next check will refresh conservatively."
        return 0
    }
    seconds_left=$(( expiration_epoch - now_epoch ))

    print "Last successful refresh: $(/usr/bin/plutil -extract lastSuccessfulInstallUTC raw "$STATE_PLIST" 2>/dev/null || print unknown)"
    print "Installed profile expires: $expiration"
    print "Seconds until expiry: $seconds_left"
    print "Refresh threshold: $REFRESH_THRESHOLD_SECONDS seconds"
}

if [[ "$MODE" == "status" ]]; then
    show_status
    exit 0
fi

if [[ "$MODE" == "dry-run" ]]; then
    recorded_expiration="$(state_expiration 2>/dev/null || true)"
    if [[ -n "$recorded_expiration" ]]; then
        now_epoch="$(/bin/date -u '+%s')"
        due_epoch=$(( now_epoch + REFRESH_THRESHOLD_SECONDS ))
        recorded_expiration_epoch="$(iso_to_epoch "$recorded_expiration" || true)"
        if [[ "$recorded_expiration_epoch" == <-> ]] && (( recorded_expiration_epoch > due_epoch )); then
            log "Dry run: $APP_DISPLAY_NAME is not due for refresh; recorded profile expires at $recorded_expiration."
        else
            log "Dry run: $APP_DISPLAY_NAME is due for refresh; recorded profile expires at $recorded_expiration."
        fi
    else
        log "Dry run: no successful managed refresh is recorded, so $APP_DISPLAY_NAME would be refreshed now."
    fi
    exit 0
fi

if ! /bin/mkdir -p "$STATE_DIR" "$LOG_DIR" "$PROFILE_BACKUP_DIR" "$DERIVED_DATA_DIR"; then
    print -u2 "Could not create $APP_DISPLAY_NAME Auto Refresh state directories."
    exit 1
fi

ATTEMPT_OUTCOME="in_progress"
ATTEMPT_MESSAGE="Refresh check started but did not reach a final result."

acquire_lock() {
    if ( set -C; print -r -- "$$" > "$LOCK_FILE" ) 2>/dev/null; then
        return 0
    fi

    local existing_pid=""
    [[ -f "$LOCK_FILE" ]] && existing_pid="$(<"$LOCK_FILE")"
    if [[ "$existing_pid" == <-> ]] && /bin/kill -0 "$existing_pid" 2>/dev/null; then
        log "Another refresh check is already running (pid $existing_pid); skipping."
        return 1
    fi

    [[ -n "$existing_pid" ]] || {
        log "The refresh lock is still being initialized; skipping this check."
        return 1
    }

    /bin/rm -f "$LOCK_FILE"
    ( set -C; print -r -- "$$" > "$LOCK_FILE" ) 2>/dev/null || {
        log "Could not acquire the refresh lock; skipping."
        return 1
    }
}

if ! acquire_lock; then
    record_result "deferred" "Another refresh check is already running; it was left undisturbed and this check was skipped."
    exit 0
fi

typeset -a QUARANTINED_ORIGINALS
typeset -a QUARANTINED_BACKUPS
KEEP_QUARANTINED=0
state_tmp=""

cleanup() {
    local exit_status=$?
    local index original backup replacement_backup replacement_suffix
    if (( KEEP_QUARANTINED == 0 )); then
        for (( index = 1; index <= ${#QUARANTINED_ORIGINALS}; index++ )); do
            original="${QUARANTINED_ORIGINALS[$index]}"
            backup="${QUARANTINED_BACKUPS[$index]}"
            replacement_backup="$backup.replacement"
            if [[ -f "$backup" && -e "$original" ]]; then
                replacement_suffix=0
                while [[ -e "$replacement_backup" ]]; do
                    replacement_suffix=$(( replacement_suffix + 1 ))
                    replacement_backup="$backup.replacement.$replacement_suffix"
                done
                if /bin/mv "$original" "$replacement_backup"; then
                    if /bin/mv "$backup" "$original"; then
                        log "Preserved Xcode's replacement profile alongside the restored cached profile."
                    else
                        log "Could not restore the quarantined profile at $original; both profiles remain in the backup directory."
                    fi
                else
                    log "Could not preserve Xcode's replacement profile at $original; leaving the cached profile backup untouched."
                fi
            elif [[ -f "$backup" ]]; then
                /bin/mv "$backup" "$original" || log "Could not restore the quarantined profile at $original."
            fi
        done
    fi
    if [[ "$ATTEMPT_OUTCOME" == "in_progress" ]]; then
        if (( exit_status == 0 )); then
            set_attempt_result "completed" "Refresh check completed without a managed installation result."
        else
            set_attempt_result "failed" "Refresh check ended before a more specific result was recorded; inspect the refresh log."
        fi
    fi
    record_result "$ATTEMPT_OUTCOME" "$ATTEMPT_MESSAGE"
    /bin/rm -f "$DEVICE_APPS_JSON" "$DEVICE_PROCESSES_JSON" "$DECODED_PROFILE"
    [[ -n "$state_tmp" ]] && /bin/rm -f "$state_tmp"
    /bin/rm -f "$LOCK_FILE"
    return "$exit_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

if [[ -f "$STATE_PLIST" ]]; then
    recorded_bundle_id="$(/usr/bin/plutil -extract bundleIdentifier raw "$STATE_PLIST" 2>/dev/null || true)"
    recorded_team_id="$(/usr/bin/plutil -extract teamIdentifier raw "$STATE_PLIST" 2>/dev/null || true)"
    if [[ "$recorded_bundle_id" != "$BUNDLE_ID" || "$recorded_team_id" != "$TEAM_ID" ]]; then
        log "$APP_DISPLAY_NAME managed state does not match the catalog bundle/team identity; refusing to build or install."
        set_attempt_result "identity_mismatch" "Managed state does not match the catalog bundle/team identity; no build, profile quarantine, or installation was attempted."
        exit 1
    fi
fi

now_epoch="$(/bin/date -u '+%s')"
due_epoch=$(( now_epoch + REFRESH_THRESHOLD_SECONDS ))
recorded_expiration="$(state_expiration 2>/dev/null || true)"

if [[ "$MODE" != "force" && -n "$recorded_expiration" ]]; then
    recorded_expiration_epoch="$(iso_to_epoch "$recorded_expiration" || true)"
    if [[ "$recorded_expiration_epoch" == <-> ]] && (( recorded_expiration_epoch > due_epoch )); then
        log "$APP_DISPLAY_NAME is not due for refresh; profile expires at $recorded_expiration."
        exit 0
    fi
fi

[[ -d "$PROJECT_PATH" ]] || {
    log "Project not found at $PROJECT_PATH."
    exit 1
}

# Check signing health once after the run is known to be due and before the
# bounded device preflight. This must not become a build gate: automatic
# signing may create an identity once an account is available in Xcode.
compute_signing_readiness

preflight_succeeded=0
preflight_attempt=1
while (( preflight_attempt <= DEVICE_PREFLIGHT_ATTEMPTS )); do
    /bin/rm -f "$DEVICE_APPS_JSON"
    if /usr/bin/xcrun devicectl device info apps \
        --device "$CORE_DEVICE_ID" \
        --bundle-id "$BUNDLE_ID" \
        --timeout 30 \
        --json-output "$DEVICE_APPS_JSON" \
        --quiet >"$DEVICE_LOG" 2>&1; then
        preflight_succeeded=1
        break
    fi

    if (( preflight_attempt < DEVICE_PREFLIGHT_ATTEMPTS )); then
        log "Device preflight attempt $preflight_attempt/$DEVICE_PREFLIGHT_ATTEMPTS failed; retrying in $DEVICE_PREFLIGHT_RETRY_DELAY_SECONDS seconds."
        /bin/sleep "$DEVICE_PREFLIGHT_RETRY_DELAY_SECONDS"
    fi
    preflight_attempt=$(( preflight_attempt + 1 ))
done

if (( preflight_succeeded == 0 )); then
    if (( SIGNING_READINESS_AVAILABLE == 0 )); then
        log "No usable connection to Noel's iPhone and signing readiness is blocked; leaving the installed app and signing profiles unchanged."
        notify_attention "$APP_DISPLAY_NAME refresh blocked: reconnect Noel's iPhone and configure an Apple ID/signing identity in Xcode Settings > Accounts."
        set_attempt_result "prerequisites_blocked" "No usable connection to Noel's iPhone after $DEVICE_PREFLIGHT_ATTEMPTS bounded preflight attempts, and no valid code-signing identity was found; reconnect the iPhone and configure an Apple ID/signing identity in Xcode Settings > Accounts. The installed app and signing profiles were left unchanged."
    else
        log "No usable connection to Noel's iPhone; leaving the installed app and signing profiles unchanged."
        notify_attention "$APP_DISPLAY_NAME needs refreshing, but Noel's iPhone is not reachable."
        set_attempt_result "device_unreachable" "No usable connection to Noel's iPhone after $DEVICE_PREFLIGHT_ATTEMPTS bounded preflight attempts; the installed app and signing profiles were left unchanged."
    fi
    exit 1
fi

installed_bundle_id="$(/usr/bin/plutil -extract result.apps.0.bundleIdentifier raw "$DEVICE_APPS_JSON" 2>/dev/null || true)"
if [[ "$installed_bundle_id" != "$BUNDLE_ID" ]]; then
    log "$APP_DISPLAY_NAME is not currently visible as an installed app; refusing a fresh install because data-preserving update semantics cannot be established."
    set_attempt_result "app_missing" "$APP_DISPLAY_NAME is not currently visible as an installed app; refusing a fresh install because data-preserving update semantics cannot be established."
    exit 1
fi

profile_value() {
    local profile="$1"
    local key="$2"
    /usr/bin/security cms -D -i "$profile" > "$DECODED_PROFILE" 2>/dev/null || return 1
    /usr/bin/plutil -extract "$key" raw "$DECODED_PROFILE" 2>/dev/null
}

quarantine_due_profiles() {
    local profile_dir profile application_id expiration expiration_epoch backup count=0
    local expected_application_id="$TEAM_ID.$BUNDLE_ID"
    local run_stamp="$(/bin/date -u '+%Y%m%dT%H%M%SZ')-$$"

    for profile_dir in \
        "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
        "$HOME/Library/MobileDevice/Provisioning Profiles"; do
        [[ -d "$profile_dir" ]] || continue
        while IFS= read -r profile; do
            application_id="$(profile_value "$profile" 'Entitlements.application-identifier' || true)"
            [[ "$application_id" == "$expected_application_id" ]] || continue
            expiration="$(profile_value "$profile" 'ExpirationDate' || true)"
            expiration_epoch="$(iso_to_epoch "$expiration" || true)"
            [[ "$expiration_epoch" == <-> ]] || continue
            if [[ "$MODE" != "force" ]] && (( expiration_epoch > due_epoch )); then
                continue
            fi

            count=$(( count + 1 ))
            backup="$PROFILE_BACKUP_DIR/$run_stamp-$count-${profile:t}"
            /bin/mv "$profile" "$backup" || return 1
            QUARANTINED_ORIGINALS+=("$profile")
            QUARANTINED_BACKUPS+=("$backup")
            if [[ "$MODE" == "force" ]]; then
                log "Temporarily quarantined $APP_DISPLAY_NAME's cached provisioning profile for a forced refresh."
            else
                log "Temporarily quarantined $APP_DISPLAY_NAME's near-expiry cached provisioning profile."
            fi
        done < <(/usr/bin/find "$profile_dir" -maxdepth 1 -type f \( -name '*.mobileprovision' -o -name '*.provisionprofile' \) -print)
    done
}

if ! quarantine_due_profiles; then
    log "Could not safely quarantine $APP_DISPLAY_NAME's near-expiry profile; aborting before build."
    exit 1
fi

log "Building a freshly signed $APP_DISPLAY_NAME app for Noel's iPhone."
if ! /usr/bin/xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "id=$BUILD_DEVICE_UDID" \
    -destination-timeout 30 \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -allowProvisioningUpdates \
    clean build \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    COMPILER_INDEX_STORE_ENABLE=NO >"$BUILD_LOG" 2>&1; then
    log "$APP_DISPLAY_NAME build/signing failed; the previous app remains installed and the old cached profile will be restored. See $BUILD_LOG."
    if /usr/bin/grep -Fq 'No Accounts: Add a new account in Accounts settings.' "$BUILD_LOG"; then
        set_attempt_result "build_failed_no_account" "$APP_DISPLAY_NAME build/signing failed because no Xcode account is available; the previous app remains installed and the old cached profile will be restored. See $BUILD_LOG."
        notify_attention "$APP_DISPLAY_NAME needs refreshing. Add your Apple ID in Xcode Settings > Accounts once, then the background retry can sign it."
    else
        set_attempt_result "build_failed" "$APP_DISPLAY_NAME build/signing failed; the previous app remains installed and the old cached profile will be restored. See $BUILD_LOG."
        notify_attention "$APP_DISPLAY_NAME needs refreshing, but command-line signing failed. Check the refresh log on your Mac."
    fi
    exit 1
fi

typeset -a built_candidates
built_candidates=()
while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    candidate_bundle_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$candidate/Info.plist" 2>/dev/null || true)"
    [[ "$candidate_bundle_id" == "$BUNDLE_ID" ]] && built_candidates+=("$candidate")
done < <(/usr/bin/find "$PRODUCT_DIR" -type d -name '*.app' -prune -print 2>/dev/null)

if (( ${#built_candidates} != 1 )); then
    log "The build produced ${#built_candidates} app bundles matching $BUNDLE_ID; refusing to install an ambiguous or missing build product."
    exit 1
fi

app_path="${built_candidates[1]}"
embedded_profile="$app_path/embedded.mobileprovision"

[[ -d "$app_path" && -f "$embedded_profile" ]] || {
    log "The build succeeded but the signed app/profile was not found in the matching app bundle; refusing to install."
    exit 1
}

built_bundle_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$app_path/Info.plist" 2>/dev/null || true)"
built_executable="$(/usr/bin/plutil -extract CFBundleExecutable raw "$app_path/Info.plist" 2>/dev/null || true)"
built_application_id="$(profile_value "$embedded_profile" 'Entitlements.application-identifier' || true)"
built_expiration="$(profile_value "$embedded_profile" 'ExpirationDate' || true)"
built_expiration_epoch="$(iso_to_epoch "$built_expiration" || true)"
built_profile_uuid="$(profile_value "$embedded_profile" 'UUID' || true)"

if [[ "$built_bundle_id" != "$BUNDLE_ID" || "$built_application_id" != "$TEAM_ID.$BUNDLE_ID" ]]; then
    log "The new app identity does not match the catalog $APP_DISPLAY_NAME identity; refusing to install."
    exit 1
fi

if [[ -z "$built_executable" || "$built_executable" == */* ]]; then
    log "The matching build product has no safe executable name; refusing to install."
    exit 1
fi

if [[ "$built_expiration_epoch" != <-> ]] || (( built_expiration_epoch <= due_epoch )); then
    log "Xcode did not produce a profile valid beyond the one-day threshold; refusing to replace the working installed app."
    exit 1
fi

if [[ -z "$built_profile_uuid" ]]; then
    log "The new provisioning profile has no UUID; refusing to install it."
    exit 1
fi

if ! /usr/bin/codesign --verify --deep --strict "$app_path" >>"$BUILD_LOG" 2>&1; then
    log "The new app failed code-signature verification; refusing to install."
    exit 1
fi

if ! /usr/bin/xcrun devicectl device info processes \
    --device "$CORE_DEVICE_ID" \
    --timeout 30 \
    --json-output "$DEVICE_PROCESSES_JSON" \
    --quiet >>"$DEVICE_LOG" 2>&1; then
    log "Could not verify whether $APP_DISPLAY_NAME is running; refusing to interrupt the app and retrying later."
    notify_attention "$APP_DISPLAY_NAME needs refreshing, but its running state could not be checked."
    set_attempt_result "device_unreachable" "Could not verify whether $APP_DISPLAY_NAME is running; refusing to interrupt the app and retrying later."
    exit 1
fi

process_marker="/${app_path:t}/$built_executable"
if /usr/bin/grep -Fq "$process_marker" "$DEVICE_PROCESSES_JSON"; then
    log "$APP_DISPLAY_NAME is currently running; leaving it uninterrupted and retrying the in-place update later."
    set_attempt_result "app_running" "$APP_DISPLAY_NAME is currently running; leaving it uninterrupted and retrying the in-place update later."
    exit 0
fi

log "Installing $APP_DISPLAY_NAME in place. The automation never issues an uninstall command."
if ! /usr/bin/xcrun devicectl device install app \
    --device "$CORE_DEVICE_ID" \
    --timeout 120 \
    "$app_path" >"$DEVICE_LOG" 2>&1; then
    log "Device installation failed; the previous installed app/data remain untouched. The signed build will be retried at the next scheduled check. See $DEVICE_LOG."
    notify_attention "$APP_DISPLAY_NAME's fresh build is ready, but it could not be installed on the iPhone."
    set_attempt_result "install_failed" "Device installation failed; the previous installed app/data remain untouched. The signed build will be retried at the next scheduled check. See $DEVICE_LOG."
    exit 1
fi

if ! /usr/bin/xcrun devicectl device info apps \
    --device "$CORE_DEVICE_ID" \
    --bundle-id "$BUNDLE_ID" \
    --timeout 30 \
    --json-output "$DEVICE_APPS_JSON" \
    --quiet >>"$DEVICE_LOG" 2>&1; then
    log "Install reported success, but the post-install device check failed; leaving state due so the next scheduled check verifies again."
    set_attempt_result "install_failed" "Install reported success, but the post-install device check failed; leaving state due so the next scheduled check verifies again."
    exit 1
fi

installed_bundle_id="$(/usr/bin/plutil -extract result.apps.0.bundleIdentifier raw "$DEVICE_APPS_JSON" 2>/dev/null || true)"
[[ "$installed_bundle_id" == "$BUNDLE_ID" ]] || {
    log "Install reported success, but $APP_DISPLAY_NAME was not visible afterward; leaving state due for retry."
    set_attempt_result "install_failed" "Install reported success, but $APP_DISPLAY_NAME was not visible afterward; leaving state due for retry."
    exit 1
}
if ! state_tmp="$(/usr/bin/mktemp "$STATE_DIR/state.plist.XXXXXX")"; then
    log "$APP_DISPLAY_NAME installed, but a temporary refresh state file could not be created; leaving the old profile available for recovery."
    exit 1
fi
if ! {
    /usr/bin/plutil -create xml1 "$state_tmp" &&
    /usr/bin/plutil -insert bundleIdentifier -string "$BUNDLE_ID" "$state_tmp" &&
    /usr/bin/plutil -insert teamIdentifier -string "$TEAM_ID" "$state_tmp" &&
    /usr/bin/plutil -insert deviceIdentifier -string "$CORE_DEVICE_ID" "$state_tmp" &&
    /usr/bin/plutil -insert profileExpirationUTC -string "$built_expiration" "$state_tmp" &&
    /usr/bin/plutil -insert profileUUID -string "$built_profile_uuid" "$state_tmp" &&
    /usr/bin/plutil -insert lastSuccessfulInstallUTC -string "$(timestamp)" "$state_tmp"
}; then
    log "$APP_DISPLAY_NAME installed, but its refresh state could not be recorded; leaving the old profile available for recovery."
    exit 1
fi
git_commit="$(current_git_commit)"
if ! /usr/bin/plutil -insert gitCommit -string "$git_commit" "$state_tmp" || \
   ! /usr/bin/plutil -lint "$state_tmp" >/dev/null || \
   ! /bin/mv "$state_tmp" "$STATE_PLIST"; then
    log "$APP_DISPLAY_NAME installed, but its refresh state could not be committed; leaving the old profile available for recovery."
    exit 1
fi

# Keep the old profile in its recoverable backup only after install and state commit succeed.
KEEP_QUARANTINED=1

set_attempt_result "success" "$APP_DISPLAY_NAME refresh succeeded; the installed profile now expires at $built_expiration."
log "$APP_DISPLAY_NAME refresh succeeded; the installed profile now expires at $built_expiration."
