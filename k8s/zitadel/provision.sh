#!/usr/bin/env bash
# Provisioning Zitadel per il lab MCP authentication (sostituisce scripts/fake_idp.py):
#   progetto "trendwatch" con ruolo "publisher", machine user "reader" e "publisher" (JWT, client credentials),
#   grant del ruolo publisher. Scrive zitadel.env con READER_JWT / PUBLISHER_JWT, come fake_idp.env.
# Idempotente: riusa progetto/ruolo/utenti esistenti; rigenera i client secret e i token (scadono dopo 12h).
set -euo pipefail

ISSUER="${ZITADEL_ISSUER:-http://zitadel.localtest.me:8080}"
PAT="$(kubectl -n zitadel get secret iam-admin-pat -o jsonpath='{.data.pat}' | base64 -d)"

api() { # api METHOD PATH [JSON]
  curl -sS -f -X "$1" "$ISSUER$2" -H "Authorization: Bearer $PAT" -H 'Content-Type: application/json' ${3:+-d "$3"}
}
api_ok_if_exists() { # come api, ma una risorsa già esistente (409) non è un errore
  local code
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X "$1" "$ISSUER$2" -H "Authorization: Bearer $PAT" \
    -H 'Content-Type: application/json' ${3:+-d "$3"})
  [[ "$code" == 2* || "$code" == 409 ]] || { echo "Zitadel $1 $2 -> HTTP $code" >&2; exit 1; }
}

# progetto con role assertion: i ruoli finiscono nel token
PROJECT_ID=$(api POST /management/v1/projects/_search \
  '{"queries":[{"nameQuery":{"name":"trendwatch","method":"TEXT_QUERY_METHOD_EQUALS"}}]}' | jq -r '.result[0].id // empty')
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID=$(api POST /management/v1/projects '{"name":"trendwatch","projectRoleAssertion":true}' | jq -r .id)
fi
api_ok_if_exists POST "/management/v1/projects/$PROJECT_ID/roles" '{"roleKey":"publisher","displayName":"Publisher"}'

machine_user() { # machine_user USERNAME -> userId (access token JWT, non opaco)
  local id
  id=$(api POST /management/v1/users/_search \
    "{\"queries\":[{\"userNameQuery\":{\"userName\":\"$1\",\"method\":\"TEXT_QUERY_METHOD_EQUALS\"}}]}" | jq -r '.result[0].id // empty')
  [ -n "$id" ] || id=$(api POST /management/v1/users/machine \
    "{\"userName\":\"$1\",\"name\":\"$1\",\"accessTokenType\":\"ACCESS_TOKEN_TYPE_JWT\"}" | jq -r .userId)
  echo "$id"
}
READER_ID=$(machine_user reader)
PUBLISHER_ID=$(machine_user publisher)
api_ok_if_exists POST "/management/v1/users/$PUBLISHER_ID/grants" "{\"projectId\":\"$PROJECT_ID\",\"roleKeys\":[\"publisher\"]}"

token() { # token USER_ID -> access token JWT (client credentials)
  local creds
  creds=$(api PUT "/management/v1/users/$1/secret" '{}')
  curl -sS -f "$ISSUER/oauth/v2/token" \
    -u "$(jq -r .clientId <<<"$creds"):$(jq -r .clientSecret <<<"$creds")" \
    -d grant_type=client_credentials \
    --data-urlencode "scope=openid urn:zitadel:iam:org:project:id:$PROJECT_ID:aud urn:zitadel:iam:org:projects:roles" \
    | jq -r .access_token
}

cat > zitadel.env <<EOF
export ZITADEL_ISSUER=$ISSUER
export ZITADEL_PROJECT_ID=$PROJECT_ID
export READER_JWT=$(token "$READER_ID")
export PUBLISHER_JWT=$(token "$PUBLISHER_ID")
EOF
echo "zitadel.env scritto (progetto $PROJECT_ID): source zitadel.env"
