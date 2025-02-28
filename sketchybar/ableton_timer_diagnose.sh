# Create a diagnostic script
cat > ~/ableton_timer_diagnose.sh << 'EOF'
#!/bin/bash

echo "=============== TIMER STATE DIAGNOSTICS ==============="
echo "Current date: $(date)"
echo ""

TIMER_DATA_DIR="$HOME/.config/sketchybar/timer_data"
TIMER_STATE_FILE="$TIMER_DATA_DIR/timer_state.json"

# Check if directory exists
echo "Checking timer data directory..."
if [ -d "$TIMER_DATA_DIR" ]; then
  echo "✅ Timer data directory exists: $TIMER_DATA_DIR"
  echo "Directory permissions: $(ls -ld "$TIMER_DATA_DIR")"
else
  echo "❌ Timer data directory does not exist: $TIMER_DATA_DIR"
fi
echo ""

# Check if file exists
echo "Checking timer state file..."
if [ -f "$TIMER_STATE_FILE" ]; then
  echo "✅ Timer state file exists: $TIMER_STATE_FILE"
  echo "File permissions: $(ls -la "$TIMER_STATE_FILE")"
  echo "File size: $(wc -c < "$TIMER_STATE_FILE") bytes"
else
  echo "❌ Timer state file does not exist: $TIMER_STATE_FILE"
fi
echo ""

# Check file content
echo "Timer state file content:"
if [ -f "$TIMER_STATE_FILE" ]; then
  cat "$TIMER_STATE_FILE"
  echo ""
  
  # Check if content is valid JSON
  if cat "$TIMER_STATE_FILE" | jq . > /dev/null 2>&1; then
    echo "✅ Content is valid JSON"
    
    # Extract key values
    running=$(jq -r '.running' "$TIMER_STATE_FILE")
    current_project=$(jq -r '.current_project' "$TIMER_STATE_FILE")
    
    echo "running: $running"
    echo "current_project: $current_project"
    
    # Check project's time
    if [ -n "$current_project" ]; then
      project_time=$(jq -r ".projects[\"$current_project\"] // \"not found\"" "$TIMER_STATE_FILE")
      echo "Time for project '$current_project': $project_time"
    fi
  else
    echo "❌ Content is NOT valid JSON"
  fi
else
  echo "No content (file doesn't exist)"
fi
echo ""

# Test file writing
echo "Testing file write capability..."
test_file="$TIMER_DATA_DIR/write_test.txt"
echo "test content" > "$test_file"
if [ -f "$test_file" ]; then
  echo "✅ Successfully wrote test file"
  rm "$test_file"
else
  echo "❌ Failed to write test file"
fi
echo ""

# Test toggle operation
echo "Testing toggle operation..."
echo "Current state before toggle:"
if [ -f "$TIMER_STATE_FILE" ]; then
  running_before=$(jq -r '.running' "$TIMER_STATE_FILE")
  echo "running: $running_before"
  
  # Toggle manually
  if [ "$running_before" == "true" ]; then
    echo "Setting running to false..."
    jq '.running = false' "$TIMER_STATE_FILE" > /tmp/temp_timer.json
  else
    echo "Setting running to true..."
    jq '.running = true' "$TIMER_STATE_FILE" > /tmp/temp_timer.json
  fi
  
  cat /tmp/temp_timer.json > "$TIMER_STATE_FILE"
  
  # Check new state
  running_after=$(jq -r '.running' "$TIMER_STATE_FILE")
  echo "running after manual toggle: $running_after"
  
  if [ "$running_before" != "$running_after" ]; then
    echo "✅ Toggle was successful"
  else
    echo "❌ Toggle failed - state did not change"
  fi
else
  echo "Cannot test toggle (file doesn't exist)"
fi

echo "=============== END DIAGNOSTICS ==============="
EOF

chmod +x ~/ableton_timer_diagnose.sh