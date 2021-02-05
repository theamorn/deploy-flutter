#!/bin/bash
# Read and change Build number in Pubspec
set -e
cd ios
fastlane buildNumber
cd ..

# Start Building App
flutter clean
flutter build apk --flavor dev --release -t lib/main_sit.dart --target-platform android-arm,android-arm64
cd android
fastlane beta &
cd ..
flutter build ios --flavor dev --release -t lib/main_sit.dart --no-codesign
cd ios
fastlane beta
cd ..

# Read pubspec.yaml to get version
function parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

eval $(parse_yaml pubspec.yaml)
pubspecVersion=$version
# Replace + with -
versionNumber=${pubspecVersion/+/-}

curl -X POST -H 'Content-type: application/json' \
--data '{"text":"Hey <!here>, iOS/Android version '$versionNumber' are released"}' \
https://hooks.slack.com/services/XXXXXX

# Post to line
curl -v -X POST https://api.line.me/v2/bot/message/push \
-H 'Content-Type: application/json' \
-H 'Authorization: Bearer XXXXXXX' \
-d '{
    "to": "XXXXXX",
    "messages":[
        {
            "type":"text",
            "text":"Hey all, iOS/Android version '$versionNumber' are released"
        }
    ]
}'

# GitLab Access Token
access_token="xxxxxx"
gitlabID=xxxxxx
# projectID 10014 for  to get all board please use https://xxxxxxx.atlassian.net/rest/agile/1.0/board
jiraID=xxxxx
#
# Add Git tags
curl --silent --request POST \
--header "PRIVATE-TOKEN: $access_token" \
"https://gitlab.com/api/v4/projects/$gitlabID/repository/tags?tag_name=$versionNumber&ref=master"
#
# Add Jira version
curl --silent POST --url 'https://XXXXX.atlassian.net/rest/api/3/version' \
--header 'Authorization: Basic XXXXX' \
--header 'Accept: application/json' \
--header 'Content-Type: application/json' \
--data '{"archived": false, "name": "'"$versionNumber"'", "projectId": "'$jiraID'", "released": false}'

# Get Transition
# 12918 is Issue ID, you can get from any id from that Board by calling jql Project below
curl --request GET \
  --url 'https://XXXXX.atlassian.net/rest/api/3/issue/12918/transitions' \
  --header 'Authorization: Basic XXXXX' \
  --header 'Accept: application/json'

# Get All user, just in case you want to assign to specific permission_handler
# curl --request GET \
#   --url 'https://XXXXX.atlassian.net/rest/api/3/users/search?maxResults=100' \
#   --header 'Authorization: Basic XXXXX' \
#   --header 'Accept: application/json' | jq -r '.[] | (.accountId + " : " + .displayName)'

# Search in jql only NEO project type REVIEWED
for idParams in $(curl --request GET \
  --url 'https://xxxxx.atlassian.net/rest/api/3/search?jql=xxxxxx' \
  --header 'Authorization: Basic xxxxx' \
  --header 'Accept: application/json' | jq -r '.issues[] | (.fields.creator.accountId + "," + .id)'); do
    params=(${idParams//,/ })
    accountID=${params[0]}
    issueID=${params[1]}

    # Assign
    curl --request PUT \
      --url "https://xxxxx.atlassian.net/rest/api/3/issue/$issueID/assignee" \
      --header 'Authorization: Basic xxxxxx' \
      --header 'Accept: application/json' \
      --header 'Content-Type: application/json' \
      --data '{
      "accountId": "'$accountID'"
      }'

    # Update Fixed version from Tag
    curl --request PUT \
      --url "https://xxxxxx.atlassian.net/rest/api/3/issue/$issueID" \
      --header 'Authorization: Basic xxxxxx' \
      --header 'Accept: application/json' \
      --header 'Content-Type: application/json' \
      --data '{
        "fields": {
          "fixVersions": [{
            "name": "'$versionNumber'"
          }]
        }
      }'

    # Move Ticket to SIT
    curl --request POST \
      --url "https://xxxxxx.atlassian.net/rest/api/3/issue/$issueID/transitions" \
      --header 'Authorization: Basic xxxxxx' \
      --header 'Accept: application/json' \
      --header 'Content-Type: application/json' \
      --data '{
        "transition": {
          "id": "61"
        }
      }'
done
