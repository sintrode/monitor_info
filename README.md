# Monitor Info
Extracts the [Extended Display Identification Data](https://en.wikipedia.org/wiki/Extended_Display_Identification_Data) (EDID) from your monitor.

# Known Limitations
This script currently only grabs the last monitor listed by `Get-WmiObject WmiMonitorID -Namespace root\wmi` and does not support CTA Extension Blocks. Both of these issues will be resolved in a future version of the script.

# Usage
`monitor_info.bat`
Like all proper scripts, run from the command line instead of double-clicking.
