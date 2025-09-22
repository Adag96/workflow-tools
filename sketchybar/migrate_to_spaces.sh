#!/bin/bash

CONFIG_DIR="$HOME/workflow-tools/sketchybar"
TODO_DATA_FILE="$CONFIG_DIR/todo_data/todos.json"
BACKUP_FILE="$CONFIG_DIR/todo_data/todos_backup_$(date +%Y%m%d_%H%M%S).json"

echo "Migrating todos to spaces format..."

# Create backup
cp "$TODO_DATA_FILE" "$BACKUP_FILE"
echo "Created backup: $BACKUP_FILE"

# Get existing todos and next_id
existing_todos=$(cat "$TODO_DATA_FILE" | jq '.todos')
next_id=$(cat "$TODO_DATA_FILE" | jq '.next_id')

# Create new spaces structure
cat > "$TODO_DATA_FILE" << EOF
{
  "spaces": {
    "Personal": {
      "name": "Personal",
      "color": "👤",
      "todos": $existing_todos
    },
    "Ujam": {
      "name": "Ujam",
      "color": "🏢",
      "todos": []
    },
    "Lonebody": {
      "name": "Lonebody",
      "color": "🎶",
      "todos": []
    },
    "60 Pleasant": {
      "name": "60 Pleasant",
      "color": "🏠",
      "todos": []
    },
    "Workflow Tools": {
      "name": "Workflow Tools",
      "color": "⚙️",
      "todos": []
    }
  },
  "current_space": "ALL",
  "next_id": $next_id
}
EOF

echo "Migration complete! All existing todos moved to 'Personal' space."
echo "New spaces created: Personal, UJAM, Lonebody, Real Estate"
echo "Current view set to 'ALL' to show all todos"