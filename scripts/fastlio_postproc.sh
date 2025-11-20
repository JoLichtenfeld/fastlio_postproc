#!/bin/bash

#######################################
# Color Codes and Log Functions
#######################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

#######################################
# Input Validation
#######################################
if [ $# -eq 0 ]; then
    print_error "No bag file provided"
    echo "Usage: fastlio_postproc <bagfile>"
    exit 1
fi

# Convert to absolute path immediately
if ! BAGFILE=$(realpath -m "$1" 2>/dev/null); then
    print_error "Invalid path: $1"
    exit 1
fi

if [ ! -e "$BAGFILE" ]; then
    print_error "Bag file does not exist: $BAGFILE"
    exit 1
fi

print_info "Using bag file: $BAGFILE"

#######################################
# Read Bag Info
#######################################
if ! BAG_INFO=$(ros2 bag info "$BAGFILE" 2>/dev/null); then
    print_error "Failed to read bag file. Is it a valid ROS2 bag?"
    exit 1
fi

#######################################
# Extract Topics
#######################################
mapfile -t IMU_TOPICS < <(echo "$BAG_INFO" | grep -E "sensor_msgs/msg/Imu" | awk '{print $2}')
mapfile -t PCL_TOPICS < <(echo "$BAG_INFO" | grep -E "sensor_msgs/msg/PointCloud2" | awk '{print $2}')
mapfile -t LIVOX_TOPICS < <(echo "$BAG_INFO" | grep -E "livox_ros_driver2/msg/CustomMsg" | awk '{print $2}')

HAS_PCL=${#PCL_TOPICS[@]}
HAS_LIVOX=${#LIVOX_TOPICS[@]}

if [ $HAS_PCL -eq 0 ] && [ $HAS_LIVOX -eq 0 ]; then
    print_error "No PointCloud2 or Livox topics found"
    exit 1
fi

print_success "Found ${#IMU_TOPICS[@]} IMU, ${#PCL_TOPICS[@]} PCL, ${#LIVOX_TOPICS[@]} Livox"

#######################################
# Topic Selection Helper
#######################################
select_topic() {
    local prompt="$1"
    shift
    local topics=("$@")

    if [ ${#topics[@]} -eq 1 ]; then
        echo "${topics[0]}"
        return
    fi

    echo -e "\n$prompt"
    select topic in "${topics[@]}"; do
        if [ -n "$topic" ]; then
            echo "$topic"
            return
        fi
        print_warning "Invalid selection"
    done
}

#######################################
# Build LIDAR Topic List
#######################################
declare -a LIDAR_RAW=()
declare -a LIDAR_TYPES=()
declare -a LIDAR_DISPLAY=()

for t in "${PCL_TOPICS[@]}"; do
    LIDAR_RAW+=("$t")
    LIDAR_TYPES+=("pointcloud2")
    LIDAR_DISPLAY+=("$t (pointcloud2)")
done

for t in "${LIVOX_TOPICS[@]}"; do
    LIDAR_RAW+=("$t")
    LIDAR_TYPES+=("livox")
    LIDAR_DISPLAY+=("$t (livox)")
done

#######################################
# User Selects Topics
#######################################
print_info "Select IMU topic:"
IMU_TOPIC=$(select_topic "Available IMU topics:" "${IMU_TOPICS[@]}")

print_success "Selected IMU topic: $IMU_TOPIC"

print_info "Select LIDAR topic:"

if [ ${#LIDAR_RAW[@]} -eq 1 ]; then
    LIDAR_TOPIC="${LIDAR_RAW[0]}"
    LIDAR_TYPE="${LIDAR_TYPES[0]}"
else
    echo -e "\nAvailable LIDAR topics:"
    select entry in "${LIDAR_DISPLAY[@]}"; do
        if [ -n "$entry" ]; then
            idx=$((REPLY-1))
            LIDAR_TOPIC="${LIDAR_RAW[$idx]}"
            LIDAR_TYPE="${LIDAR_TYPES[$idx]}"
            break
        fi
        print_warning "Invalid selection"
    done
fi

print_success "Selected LIDAR topic: $LIDAR_TOPIC ($LIDAR_TYPE)"

#######################################
# Package Directory Paths
#######################################
PKG_PREFIX=$(ros2 pkg prefix fastlio_postproc)
CONFIG_DIR=$(realpath -m "$PKG_PREFIX/share/fastlio_postproc/config")
TEMPLATE_DIR=$(realpath -m "$PKG_PREFIX/share/fastlio_postproc/templates")
SCRIPT_DIR="$PKG_PREFIX/share/fastlio_postproc/scripts"

#######################################
# Sensor preset selection (simplified)
#######################################
if [ "$LIDAR_TYPE" = "livox" ]; then
    # Livox CustomMsg implies mid360
    SENSOR_PRESET="livox_mid360"
    print_info "Detected Livox CustomMsg -> using preset: $SENSOR_PRESET"
    LIDAR_TYPE_INT=1
else
    # PointCloud2: ask user which sensor produced it
    print_info "PointCloud2 source: select sensor type (ouster or livox)"
    select sensor_type in ouster livox; do
        case "$sensor_type" in
            ouster)
                SENSOR_PRESET="ouster128"; break ;;
            livox)
                SENSOR_PRESET="livox_mid360"; break ;;
            *) print_warning "Invalid selection" ;;
        esac
    done
    # Map vendor + message type to integer code
    if [ "$SENSOR_PRESET" = "ouster128" ]; then
        LIDAR_TYPE_INT=3
    else
        # Livox publishing PointCloud2
        LIDAR_TYPE_INT=4
    fi
fi

print_success "Selected sensor preset: $SENSOR_PRESET"

TEMPLATE_CONFIG_FILE="${TEMPLATE_DIR}/${SENSOR_PRESET}_config.yaml.j2"
OUTPUT_CONFIG_FILE="${CONFIG_DIR}/${SENSOR_PRESET}_config.yaml"

if [ ! -f "$TEMPLATE_CONFIG_FILE" ]; then
    print_error "Missing config template: $TEMPLATE_CONFIG_FILE"
    exit 1
fi

#######################################
# Render YAML Config (Jinja2)
#######################################
python3 "$SCRIPT_DIR/render_jinja.py" \
    "$TEMPLATE_CONFIG_FILE" "$OUTPUT_CONFIG_FILE" \
    lidar_topic="$LIDAR_TOPIC" imu_topic="$IMU_TOPIC" \
    lidar_type="$LIDAR_TYPE_INT" sensor_preset="$SENSOR_PRESET"

print_success "Config generated: $OUTPUT_CONFIG_FILE"

#######################################
# RViz Config
#######################################
TEMPLATE_RVIZ_FILE="${TEMPLATE_DIR}/fast_lio.rviz.j2"
RVIZ_OUTPUT_FILE="${CONFIG_DIR}/fast_lio.rviz"

python3 "$SCRIPT_DIR/render_jinja.py" \
    "$TEMPLATE_RVIZ_FILE" "$RVIZ_OUTPUT_FILE" \
    cloud_registered_topic="/cloud_registered" \
    map_topic="/Laser_map" \
    || { print_warning "Failed to render RViz template"; }

#######################################
# Prepare Commands
#######################################
FAST_LIO_CMD="ros2 launch fast_lio mapping.launch.py config_path:=$CONFIG_DIR config_file:=$(basename "$OUTPUT_CONFIG_FILE") rviz:=False"
BAG_CMD="sleep 1; ros2 bag play \"$BAGFILE\" --topic $IMU_TOPIC $LIDAR_TOPIC"
RVIZ_CMD="rviz2 -d \"$RVIZ_OUTPUT_FILE\""

print_info "FAST-LIO command: $FAST_LIO_CMD"
print_info "bag play command: $BAG_CMD"
print_info "rviz command: $RVIZ_CMD"

#######################################
# Start tmux session
#######################################
if ! command -v tmux >/dev/null 2>&1; then
    print_error "tmux not found"
    exit 1
fi

SESSION_NAME="fastlio_$(basename "$BAGFILE" | tr -c '[:alnum:]_.-' '_')"
# Create panes instead of separate windows
BAG_DIR="$(dirname "$BAGFILE")"

print_info "Starting tmux session with 3 panes (top-left=bag, top-right=rviz, bottom=fast_lio)"

# Start session with bottom pane running fast_lio
tmux new-session -d -s "$SESSION_NAME" -c "$BAG_DIR" -n main "bash -lc \"$FAST_LIO_CMD\"" || { print_error "Failed to create tmux session"; exit 1; }

# Create a top pane above for bag playback (new pane becomes active by default)
tmux split-window -v -b -t "$SESSION_NAME":0 "bash -lc \"$BAG_CMD\"" || { print_error "Failed to create bag_play top pane"; tmux kill-session -t "$SESSION_NAME" >/dev/null 2>&1; exit 1; }

# Split the active top pane horizontally for rviz on the right
tmux split-window -h -t "$SESSION_NAME":0 "bash -lc \"$RVIZ_CMD\"" || print_warning "Failed to create rviz right pane (continuing)"

# Try a balanced grid; user can adjust manually if desired
tmux select-layout -t "$SESSION_NAME":0 tiled >/dev/null 2>&1 || true

# Attach
tmux attach-session -t "$SESSION_NAME" || print_warning "Could not attach to tmux session (running detached)"

print_success "FAST-LIO tmux session started"
