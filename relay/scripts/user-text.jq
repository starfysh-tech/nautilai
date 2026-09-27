# user_text: the text a user typed on one transcript line, or nothing.
# Shared by extract-transcript.sh and haiku-narrative.sh via
# `jq -L <scripts dir> 'include "user-text"; ...'`.
#
# Structural exclusions: isMeta flags harness-injected content (skill prompts
# etc.); isCompactSummary flags compaction continuations the user never typed.
# These are the primary defense. The leading-tag check is a heuristic
# secondary defense for injections that carry no structural marker: a message
# opening with a hyphenated-tag XML opener (<local-command-stdout>,
# <system-reminder>, <task-notification>, <teammate-message>, ...) is almost
# certainly a harness wrapper. Every harness wrapper tag observed is
# hyphenated, while bare HTML a user might paste (<div>, <!DOCTYPE) is not.
# Accepted miss: a hyphenated custom element like <my-component> is excluded
# too. The two literal prefixes carry no tag-shaped marker.
def user_text:
  select(.type == "user")
  | select(.isMeta != true)
  | select(.isCompactSummary != true)
  | .message.content as $c
  | (
      if ($c | type) == "string" then $c
      elif ($c | type) == "object" then $c.text // null
      elif ($c | type) == "array" then
        ([$c[] | select(.type == "text") | .text] | join("\n")) as $joined
        | (if ($joined | length) > 0 then $joined else null end)
      else null
      end
    ) as $raw
  # A slash command arrives as <command-name>/<command-args> tags; keep the
  # command and its args when args are present, since the user typed them.
  | (if $raw != null and ($raw | startswith("<command-")) then
       ([$raw | capture("<command-args>(?<a>[\\s\\S]*?)</command-args>") | .a] | first // "") as $a
       | if ($a | test("\\S")) then
           ([$raw | capture("<command-name>(?<n>[^<]*)</command-name>") | .n] | first // "") + " " + $a
         else $raw end
     else $raw end) as $text
  | select($text != null)
  | select(
      ($text | test("^<[a-z][a-z0-9]*-[a-z0-9-]*[ >]") | not)
      and ($text | startswith("Base directory for this skill") | not)
      and ($text | startswith("Another Claude session sent a message:") | not)
    )
  | $text;
