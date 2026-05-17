#!/bin/bash
################################################################################
# VM Health Check Script for Ubuntu
#
# Description:
#   Analyzes the health of an Ubuntu virtual machine by inspecting CPU usage,
#   memory usage, and disk usage. Reports overall VM status as HEALTHY or
#   NOT HEALTHY based on a 60% utilization threshold.
#
# Usage:
#   ./vm_health_check.sh           # Display health status with exit code 0 or 1
#   ./vm_health_check.sh explain   # Display health status + detailed explanation
#
# Exit Codes:
#   0 - Overall status is HEALTHY
#   1 - Overall status is NOT HEALTHY
#   2 - Invalid argument supplied
#
# Requirements:
#   - Ubuntu 20.04 or later
#   - Bash 5+
#   - GNU coreutils (top, free, df)
#
################################################################################

set -euo pipefail

# ANSI color codes for terminal output
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_RESET='\033[0m'

# Health threshold (percentage)
readonly THRESHOLD=60

# Flag to enable colored output (only if stdout is a TTY)
ENABLE_COLOR=1
if [[ ! -t 1 ]]; then
    ENABLE_COLOR=0
fi

################################################################################
# Function: colorize
# Description: Apply color codes to text if output is to a terminal
# Arguments:
#   $1 - Color code (COLOR_GREEN or COLOR_RED)
#   $2 - Text to colorize
# Returns: Colored text or plain text depending on ENABLE_COLOR flag
################################################################################
colorize() {
    local color="$1"
    local text="$2"
    
    if [[ $ENABLE_COLOR -eq 1 ]]; then
        echo -ne "${color}${text}${COLOR_RESET}"
    else
        echo -n "$text"
    fi
}

################################################################################
# Function: get_cpu_usage
# Description: Calculate CPU usage as a percentage using /proc/stat
# Logic: 
#   - Reads two samples of /proc/stat separated by a 1-second interval
#   - Calculates CPU time (user + nice + system + irq + softirq)
#   - Idle time is subtracted from total; result is percentage
# Returns: CPU usage percentage (integer)
################################################################################
get_cpu_usage() {
    # Read initial /proc/stat
    local stat1
    stat1=$(head -n 1 /proc/stat)
    
    # Extract CPU time values (columns 2-8: user, nice, system, idle, iowait, irq, softirq)
    local cpu1_user cpu1_nice cpu1_system cpu1_idle cpu1_iowait cpu1_irq cpu1_softirq
    read -r _ cpu1_user cpu1_nice cpu1_system cpu1_idle cpu1_iowait cpu1_irq cpu1_softirq <<< "$stat1"
    
    # Sleep for 1 second to allow CPU activity measurement
    sleep 1
    
    # Read second /proc/stat
    local stat2
    stat2=$(head -n 1 /proc/stat)
    
    # Extract CPU time values
    local cpu2_user cpu2_nice cpu2_system cpu2_idle cpu2_iowait cpu2_irq cpu2_softirq
    read -r _ cpu2_user cpu2_nice cpu2_system cpu2_idle cpu2_iowait cpu2_irq cpu2_softirq <<< "$stat2"
    
    # Calculate deltas for all CPU time components
    local delta_user=$((cpu2_user - cpu1_user))
    local delta_nice=$((cpu2_nice - cpu1_nice))
    local delta_system=$((cpu2_system - cpu1_system))
    local delta_idle=$((cpu2_idle - cpu1_idle))
    local delta_iowait=$((cpu2_iowait - cpu1_iowait))
    local delta_irq=$((cpu2_irq - cpu1_irq))
    local delta_softirq=$((cpu2_softirq - cpu1_softirq))
    
    # Calculate total CPU time (work + idle)
    local total_time=$((delta_user + delta_nice + delta_system + delta_idle + delta_iowait + delta_irq + delta_softirq))
    
    # Avoid division by zero
    if [[ $total_time -eq 0 ]]; then
        echo 0
        return 0
    fi
    
    # Calculate active CPU time (total - idle)
    local active_time=$((total_time - delta_idle))
    
    # Calculate percentage (integer division: active / total × 100)
    local cpu_percent=$((active_time * 100 / total_time))
    
    echo "$cpu_percent"
}

################################################################################
# Function: get_memory_usage
# Description: Calculate memory usage as a percentage using free command
# Logic:
#   - Runs `free -m` to get memory stats in MB
#   - Extracts used and total memory (excludes swap)
#   - Calculates percentage: (used / total) × 100
# Returns: Memory usage percentage (integer)
################################################################################
get_memory_usage() {
    # Run free command and extract memory line (second line after header)
    local mem_line
    mem_line=$(free -m | awk 'NR==2 {print $2, $3}')
    
    local mem_total mem_used
    read -r mem_total mem_used <<< "$mem_line"
    
    # Avoid division by zero
    if [[ $mem_total -eq 0 ]]; then
        echo 0
        return 0
    fi
    
    # Calculate percentage (integer division: used / total × 100)
    local mem_percent=$((mem_used * 100 / mem_total))
    
    echo "$mem_percent"
}

################################################################################
# Function: get_disk_usage
# Description: Extract disk usage percentage for root filesystem
# Logic:
#   - Runs `df -h /` to get filesystem stats for root partition
#   - Extracts the "Use%" column (5th field in the output)
#   - Removes the '%' character and returns the integer value
# Returns: Disk usage percentage (integer)
################################################################################
get_disk_usage() {
    # Run df command for root filesystem and extract Use% column
    local disk_percent
    disk_percent=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    # Ensure we have a valid number (defensive check)
    if ! [[ "$disk_percent" =~ ^[0-9]+$ ]]; then
        echo 0
        return 0
    fi
    
    echo "$disk_percent"
}

################################################################################
# Function: check_health
# Description: Determine if a metric is healthy based on threshold
# Arguments:
#   $1 - Metric value (percentage)
# Returns: 
#   Echoes "HEALTHY" if value < THRESHOLD, "NOT HEALTHY" otherwise
################################################################################
check_health() {
    local value="$1"
    
    if [[ $value -lt $THRESHOLD ]]; then
        echo "HEALTHY"
    else
        echo "NOT HEALTHY"
    fi
}

################################################################################
# Function: print_metric_line
# Description: Format and print a single metric line with color coding
# Arguments:
#   $1 - Metric name (e.g., "CPU Usage")
#   $2 - Metric value (percentage)
#   $3 - Health status ("HEALTHY" or "NOT HEALTHY")
################################################################################
print_metric_line() {
    local metric_name="$1"
    local metric_value="$2"
    local health_status="$3"
    
    # Determine color based on health status
    local color
    if [[ "$health_status" == "HEALTHY" ]]; then
        color=$COLOR_GREEN
    else
        color=$COLOR_RED
    fi
    
    # Format: "  Metric Name      : <value>%  [STATUS]"
    printf "  %-16s: %3d%%  " "$metric_name" "$metric_value"
    colorize "$color" "[$health_status]"
    echo ""
}

################################################################################
# Function: print_overall_status
# Description: Print the overall VM status line with color coding
# Arguments:
#   $1 - Overall status ("HEALTHY" or "NOT HEALTHY")
################################################################################
print_overall_status() {
    local overall_status="$1"
    
    # Determine color based on overall status
    local color
    if [[ "$overall_status" == "HEALTHY" ]]; then
        color=$COLOR_GREEN
    else
        color=$COLOR_RED
    fi
    
    echo "  ─────────────────────────────────────────────────"
    printf "  %-16s: " "Overall VM Status"
    colorize "$color" "$overall_status"
    echo ""
}

################################################################################
# Function: print_explanation
# Description: Print detailed explanation of health status
# Arguments:
#   $1 - Overall status
#   $2 - CPU usage and health
#   $3 - Memory usage and health
#   $4 - Disk usage and health
################################################################################
print_explanation() {
    local overall_status="$1"
    local cpu_value="$2"
    local cpu_health="$3"
    local mem_value="$4"
    local mem_health="$5"
    local disk_value="$6"
    local disk_health="$7"
    
    echo ""
    echo "─────────────────────────────────────────────────"
    echo "Explanation:"
    echo ""
    
    if [[ "$overall_status" == "HEALTHY" ]]; then
        echo "All metrics are within acceptable limits. Your VM is operating"
        echo "normally with CPU at ${cpu_value}%, Memory at ${mem_value}%, and Disk at ${disk_value}%,"
        echo "all below the 60% threshold. No immediate action is required."
    else
        echo "One or more metrics exceed the 60% threshold. Details:"
        
        if [[ "$cpu_health" == "NOT HEALTHY" ]]; then
            echo "  • CPU Usage (${cpu_value}%): High CPU utilization detected."
            echo "    Remediation: Identify and kill idle/runaway processes using 'top' or 'ps'."
            echo "    Consider scheduling batch jobs during off-peak hours."
        fi
        
        if [[ "$mem_health" == "NOT HEALTHY" ]]; then
            echo "  • Memory Usage (${mem_value}%): High memory consumption detected."
            echo "    Remediation: Review running processes with 'ps aux' or 'free -h'."
            echo "    Consider adding more RAM or optimizing application memory usage."
        fi
        
        if [[ "$disk_health" == "NOT HEALTHY" ]]; then
            echo "  • Disk Usage (${disk_value}%): Low disk space remaining."
            echo "    Remediation: Clean up old logs/temp files with 'ncdu' or 'du -sh /*'."
            echo "    Consider archiving or removing unnecessary data."
        fi
    fi
    
    echo ""
}

################################################################################
# Main Script Logic
################################################################################

# Parse command-line arguments
EXPLAIN_FLAG=0
if [[ $# -gt 0 ]]; then
    if [[ "$1" == "explain" ]]; then
        EXPLAIN_FLAG=1
    else
        echo "Error: Invalid argument '$1'" >&2
        echo "Usage: $0 [explain]" >&2
        exit 2
    fi
fi

# Collect metrics
cpu_usage=$(get_cpu_usage)
memory_usage=$(get_memory_usage)
disk_usage=$(get_disk_usage)

# Determine health status for each metric
cpu_health=$(check_health "$cpu_usage")
memory_health=$(check_health "$memory_usage")
disk_health=$(check_health "$disk_usage")

# Determine overall status (HEALTHY only if ALL metrics are below threshold)
if [[ "$cpu_health" == "HEALTHY" ]] && [[ "$memory_health" == "HEALTHY" ]] && [[ "$disk_health" == "HEALTHY" ]]; then
    overall_status="HEALTHY"
    exit_code=0
else
    overall_status="NOT HEALTHY"
    exit_code=1
fi

# Print status table
echo ""
print_metric_line "CPU Usage" "$cpu_usage" "$cpu_health"
print_metric_line "Memory Usage" "$memory_usage" "$memory_health"
print_metric_line "Disk Usage" "$disk_usage" "$disk_health"
print_overall_status "$overall_status"
echo ""

# Print explanation if requested
if [[ $EXPLAIN_FLAG -eq 1 ]]; then
    print_explanation "$overall_status" "$cpu_usage" "$cpu_health" "$memory_usage" "$memory_health" "$disk_usage" "$disk_health"
fi

exit "$exit_code"
