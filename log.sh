#!/bin/sh

# Usage: ./log.sh <company/project> [start_date] [end_date]

BOOK_NAME="$1"
START_DATE="$2"
END_DATE="$3"
BOOK_FILE="books/$BOOK_NAME.md"
REPO_FILE="repositories.json"
DEFAULT_COMMENT="Commit on a private project"

if [ -z "$BOOK_NAME" ]; then
    echo "Usage: $0 <company/project> [start_date: YYYY-MM-DD] [end_date: YYYY-MM-DD]"
    exit 1
fi

if [ ! -f "$REPO_FILE" ]; then
    echo "❌ Error: '$REPO_FILE' not found. Please create it with a JSON array of repository names."
    exit 1
fi

USERNAME=$(gh api user --jq '.login' 2>/dev/null)
if [ -z "$USERNAME" ]; then
    echo "❌ Error: Could not determine GitHub username. Make sure you're authenticated via 'gh auth login'."
    exit 1
fi

mkdir -p "$(dirname "$BOOK_FILE")"
touch "$BOOK_FILE"

if [ -z "$START_DATE" ]; then
    LAST_DATE=$(grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "$BOOK_FILE" \
        | sort | tail -n 1 | awk '{print $1}')
    if [ -z "$LAST_DATE" ]; then
        START_DATE="2000-01-01T00:00:00Z"
        echo "ℹ️  No previous date found. Using fallback: $START_DATE"
    else
        START_DATE=$(date -u -d "$LAST_DATE +1 second" +'%Y-%m-%dT%H:%M:%SZ')
        echo "ℹ️  Resuming from last date +1s: $START_DATE"
    fi
else
    if ! echo "$START_DATE" | grep -Eq 'T[0-9]{2}:'; then
        START_DATE="${START_DATE}T00:00:00Z"
    fi
fi

echo "👤 GitHub user: $USERNAME"
echo "📚 Logging to: $BOOK_FILE"
echo "📅 Range: $START_DATE → ${END_DATE:-now}"
echo "📦 Repositories: from $REPO_FILE"
echo

REPOS=$(jq -r '.[]' "$REPO_FILE")

for REPO in $REPOS; do
    echo "🔍 Scanning $REPO..."

    REPO_CHECK=$(gh api "repos/$REPO" 2>/dev/null)
    if [ -z "$REPO_CHECK" ]; then
        echo "❌ Skipping invalid or inaccessible repo: $REPO"
        continue
    fi

    COMMITS=$(gh api -X GET "repos/$REPO/commits" \
        -f author="$USERNAME" \
        -f since="${START_DATE}" \
        ${END_DATE:+-f until="${END_DATE}T23:59:59Z"} \
        --jq '.[] | "\(.commit.author.date) \(.sha)"' 2>/dev/null)

    if [ -z "$COMMITS" ]; then
        echo "ℹ️  No commits found for $REPO in given range."
        continue
    fi

    echo "$COMMITS" | tac | while read -r line; do
        COMMIT_DATE=$(echo "$line" | awk '{print $1}')
        echo "$COMMIT_DATE - $DEFAULT_COMMENT" >> "$BOOK_FILE"
        echo "✔ Logged: $COMMIT_DATE"
        git add "$BOOK_FILE"
        GIT_AUTHOR_DATE="$ISO_DATE" GIT_COMMITTER_DATE="$ISO_DATE" \
            git commit -m "$DEFAULT_COMMENT" >/dev/null
    done
done
