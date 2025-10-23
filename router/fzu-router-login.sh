#!/bin/sh
#
# fzu-router-login.sh - campus ePortal login
# Requires: curl sed awk grep tr
# Config in /etc/fzu-login.conf (username=... password=... user_agent=...)
# Make executable: chmod +x /etc/fzu-router-login.sh

# ---------- Config ----------
CONFIG_FILE="/etc/fzu-login.conf"
USER_AGENT_DEFAULT=""
MAX_RETRIES=3
CHECK_URL="http://www.gstatic.com/generate_204"

LOGIN_HOST="172.16.0.46"
PAGEINFO_PATH="/eportal/InterFace.do?method=pageInfo"
GETONLINE_PATH="/eportal/InterFace.do?method=getOnlineUserInfo"
LOGIN_PATH="/eportal/InterFace.do?method=login"
LOGOUT_PATH="/eportal/InterFace.do?method=logout"

username=""
password=""
user_agent=""

# ---------- Helpers ----------
log() {
  echo "$(date '+%F %T') - $*"
}

check_dependencies() {
  for cmd in curl sed awk grep tr; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log "ERROR: required command '$cmd' not found"
      return 1
    fi
  done
  return 0
}

read_config() {
  if [ -f "$CONFIG_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line=$(echo "$line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [ -z "$line" ] && continue
      case "$line" in \#*) continue ;; esac
      if echo "$line" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*='; then
        eval "$line"
      fi
    done < "$CONFIG_FILE"
  fi
  [ -z "$user_agent" ] && user_agent="$USER_AGENT_DEFAULT"
  if [ -z "$username" ] || [ -z "$password" ]; then
    log "ERROR: username or password not set. Edit $CONFIG_FILE"
    return 1
  fi
  return 0
}

extract_json_field() {
  json="$1"
  field="$2"
  val=$(printf "%s\n" "$json" | sed -n 's/.*"'$field'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
  [ -n "$val" ] && { printf "%s" "$val"; return 0; }
  val=$(printf "%s\n" "$json" | sed -n 's/.*"'$field'"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p' | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  printf "%s" "$val"
  return 0
}

is_valid_json() {
  json="$1"
  echo "$json" | tr -d '\r\n' | grep -qE '^\s*[\{\[]' && echo yes || echo no
}

# ---------- Portal functions ----------
check_online() {
  url="http://${LOGIN_HOST}${GETONLINE_PATH}"
  resp=$(curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" --data-urlencode "userIndex=" "$url" 2>/dev/null)
  curl_exit_code=$?
  if [ "$(is_valid_json "$resp")" != "yes" ]; then
    log "check_online: response not valid JSON"
    log "raw: $resp (curl: $curl_exit_code)"
    return 3
  fi

  result=$(extract_json_field "$resp" "result")
  userindex=$(extract_json_field "$resp" "userIndex")
  message=$(extract_json_field "$resp" "message")
  userName=$(extract_json_field "$resp" "userName")
  userId=$(extract_json_field "$resp" "userId")
  userIp=$(extract_json_field "$resp" "userIp")
  userMac=$(extract_json_field "$resp" "userMac")

  log "Status Message: $message"
  [ -n "$userName" ] && log "Username: $userName"
  [ -n "$userId" ] && log "User ID: $userId"
  [ -n "$userIp" ] && log "User IP: $userIp"
  [ -n "$userMac" ] && log "User MAC: $userMac"
  [ -n "$userindex" ] && log "Device ID (userIndex): $userindex"

  case "$result" in
    success) return 0 ;;
    fail)    return 1 ;;
    wait)    return 2 ;;
    *)       return 3 ;;
  esac
}

get_page_info() {
  referer_url="$1"
  encoded_query_string="$2"
  JSESSIONID="$3"
  url="http://${LOGIN_HOST}${PAGEINFO_PATH}"
  _resp=$(curl -s -X POST \
    -H "Host: ${LOGIN_HOST}" \
    -H "Connection: keep-alive" \
    -H "User-Agent: ${user_agent}" \
    -H "DNT: 1" \
    -H "Accept: */*" \
    -H "Origin: http://${LOGIN_HOST}" \
    -H "Referer: ${referer_url}" \
    -H "Accept-Language: zh-CN,zh;q=0.9" \
    -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
    --cookie "JSESSIONID=${JSESSIONID}" \
    --data-urlencode "queryString=${encoded_query_string}" \
    "$url" 2>/dev/null)
  # we don't store to file; function returns success anyway
  return 0
}

logout() {
  userindex_arg="$1"
  url="http://${LOGIN_HOST}${LOGOUT_PATH}"
  resp=$(curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" -H "User-Agent: ${user_agent}" --data-urlencode "userIndex=${userindex_arg}" "$url" 2>/dev/null)
  curl_exit_code=$?
  if [ "$(is_valid_json "$resp")" != "yes" ]; then
    log "Logout: invalid JSON response"
    log "raw: $resp (curl: $curl_exit_code)"
    return 1
  fi
  result=$(extract_json_field "$resp" "result")
  if [ "$result" = "success" ]; then
    log "Logout device successful."
    return 0
  else
    msg=$(extract_json_field "$resp" "message")
    log "Logout device failed, msg: $msg"
    return 1
  fi
}

discover_login_page() {
  log "Discovering captive portal using $CHECK_URL ..."
  final_url=$(curl -s -L -o /dev/null -w '%{url_effective}' "$CHECK_URL" 2>/dev/null)
  log "Detected portal final URL: $final_url"
  printf "%s" "$final_url"
}

login() {
  probe_url="http://123.123.123.123"
  page_content=$(curl -s -L "$probe_url" 2>/dev/null)

  redirect_url=$(printf "%s\n" "$page_content" | sed -n "s/.*location\.href=['\"]\([^'\"]*\)['\"].*/\1/p" | head -n1)
  if [ -z "$redirect_url" ]; then
    redirect_url=$(printf "%s\n" "$page_content" | sed -n "s/.*http-equiv=['\"]refresh['\"].*url=\([^'\"]*\).*/\1/Ip" | head -n1)
  fi

  if [ -z "$redirect_url" ]; then
    redirect_url=$(discover_login_page)
    if [ -z "$redirect_url" ]; then
      log "Unable to discover redirect URL."
      return 1
    fi
  fi

  log "Redirect URL: $redirect_url"

  # fetch headers (follow redirects) and capture Set-Cookie lines to extract JSESSIONID
  headers=$(curl -s -D - -o /dev/null -L "$redirect_url" 2>/dev/null)
  JSESSIONID=$(printf "%s\n" "$headers" | grep -i 'Set-Cookie:' | sed -n 's/.*JSESSIONID=\([^;]*\).*/\1/p' | head -n1)

  # extract query string part
  query_string=$(printf "%s\n" "$redirect_url" | sed -n 's/^[^?]*?\(.*\)$/\1/p' | head -n1)

  # call pageInfo (we ignore its response here)
  get_page_info "$redirect_url" "$query_string" "$JSESSIONID"

  # login POST
  url="http://${LOGIN_HOST}${LOGIN_PATH}"
  resp=$(curl -s -X POST \
    -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
    -H "Referer: ${redirect_url}" \
    -H "Accept-Language: zh-CN,zh;q=0.9" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Origin: http://${LOGIN_HOST}" \
    -H "DNT: 1" \
    -H "Accept: */*" \
    -H "User-Agent: ${user_agent}" \
    -H "Connection: keep-alive" \
    -H "Host: ${LOGIN_HOST}" \
    --cookie "JSESSIONID=${JSESSIONID}" \
    --data-urlencode "userId=${username}" \
    --data-urlencode "password=${password}" \
    --data-urlencode "queryString=${query_string}" \
    --data-urlencode "passwordEncrypt=false" \
    --data-urlencode "validcode=" \
    --data-urlencode "operatorUserId=" \
    --data-urlencode "operatorPwd=" \
    --data-urlencode "service=" \
    "$url" 2>/dev/null)
  curl_exit_code=$?
  if [ "$(is_valid_json "$resp")" != "yes" ]; then
    log "Login failed: not valid JSON response."
    log "raw: $resp (curl: $curl_exit_code)"
    return 1
  fi

  result=$(extract_json_field "$resp" "result")
  if [ "$result" = "success" ]; then
    log "Login successful."
    return 0
  else
    msg=$(extract_json_field "$resp" "message")
    log "Login failed. Message: $msg"
    return 1
  fi
}

# ---------- Main ----------
main() {
  check_dependencies || exit 1
  read_config || exit 1

  retries=0
  while [ "$retries" -lt "$MAX_RETRIES" ]; do
    check_online
    status=$?
    case "$status" in
      0)
        log "Already online. Exiting."
        return 0
        ;;
      1)
        log "Offline — attempting login..."
        if login; then
          log "Login attempt succeeded."
          retries=0
          sleep 2
          continue
        else
          log "Login attempt failed."
          return 1
        fi
        ;;
      2)
        log "Status: wait (session pending)."
        retries=$((retries+1))
        if [ "$retries" -ge "$MAX_RETRIES" ]; then
          if [ -n "$userindex" ]; then
            if logout "$userindex"; then
              if login; then
                log "Login successful after logout."
                return 0
              else
                log "Login failed after logout."
                return 1
              fi
            else
              log "Logout failed."
              return 1
            fi
          else
            log "No userIndex available to logout."
            return 1
          fi
        fi
        sleep 5
        ;;
      3)
        log "Error parsing server response."
        return 1
        ;;
      *)
        log "Unexpected status: $status"
        return 1
        ;;
    esac
  done

  log "Main loop exit."
  return 0
}

main "$@"