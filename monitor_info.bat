::------------------------------------------------------------------------------
:: NAME
::     monitor_info.bat
::
:: DESCRIPTION
::     A batch version of Nirsoft's MonitorInfoView
::
:: AUTHOR
::     sintrode
::
:: THANKS
::     https://superuser.com/questions/1597994
::     https://superuser.com/questions/1058802
::     https://en.wikipedia.org/wiki/Extended_Display_Identification_Data
::     https://people.freedesktop.org/~imirkin/edid-decode
::     https://glenwing.github.io/docs/VESA-EEDID-A2.pdf
::
:: TODO
::     - Add support for multiple monitors
::------------------------------------------------------------------------------
@echo off
setlocal enabledelayedexpansion
cls

call :initConstants
call :getEdid || (
    echo ERROR: Valid EDID not found. Aborting.
    echo This may be caused by the script running on a VM.
    exit /b 1
)
call :extractData   8   9 manufacturer_id           bin BE
call :extractData  10  11 manufacturer_product_code hex LE
call :extractData  12  15 raw_serial                int LE
call :extractData  16  16 week_of_manufacture       int BE
call :extractData  17  17 year_of_manufacture       int BE
call :extractData  18  18 edid_version              int BE
call :extractData  19  19 edid_revision             int BE
call :extractData  20  20 basic_display             bin BE
call :extractData  21  21 horiz_size_cm             int BE
call :extractData  22  22 vert_size_cm              int BE
call :extractData  23  23 display_gamma             int BE
call :extractData  24  24 supported_features        bin BE
call :extractData  25  25 rg_ls_bits                bin BE
call :extractData  26  26 bw_ls_bits                bin BE
call :extractData  27  28 rxy_ms_bits               bin BE
call :extractData  29  30 gxy_ms_bits               bin BE
call :extractData  31  32 bxy_ms_bits               bin BE
call :extractData  33  34 wxy_ms_bits               bin BE
call :extractData  35  35 timing_1                  bin BE
call :extractData  36  36 timing_2                  bin BE
call :extractData  37  37 timing_3                  bin BE
call :extractData  38  53 standard_timing           hex BE
call :extractData  54  71 timing_descriptor_1       bin BE
call :extractData  72  89 timing_descriptor_2       bin BE
call :extractData  90 107 timing_descriptor_3       bin BE
call :extractData 108 125 timing_descriptor_4       bin BE
call :extractData 126 126 extension_blocks          int BE

set /a year_of_manufacture+=1990
set /a "display_gamma+=100", "gamma_ipart=display_gamma/100", "gamma_fpart=display_gamma%%100"

call :parseManufacturerId
call :parseBasicParameters
call :parseSupportedFeatures
call :getChromaticityCoordinates
call :parseTimingBitmap
call :parseStandardTiming
call :parseDetailedTimingDescriptor "!timing_descriptor_1!" dtd_string
call :parseDetailedTimingDescriptor "!timing_descriptor_2!" dtd_string_2
call :parseDetailedTimingDescriptor "!timing_descriptor_3!" dtd_string_3
call :parseDetailedTimingDescriptor "!timing_descriptor_4!" dtd_string_4

if not defined max_res call :getMaxResolution
if not defined friendly_name call :getAsciiWmiValue UserFriendlyName friendly_name
if not defined friendly_serial call :getAsciiWmiValue SerialNumberId   friendly_serial
if not defined maker_name call :getAsciiWmiValue ManufacturerName maker_name

echo EDID Version:               %edid_version%.%edid_revision%
echo Model:                      %friendly_name%
echo Serial Number:              %friendly_serial% (%raw_serial%)
echo:
echo Manufacturer:               %pnp_name%
echo Manufacturer Product Code:  %manufacturer_product_code%
echo Manufacturing Period:       Week %week_of_manufacture% of %year_of_manufacture%
echo:
echo Maximum Resolution:         %max_res%
echo Physical Dimensions:        %horiz_size_cm% cm x %vert_size_cm% cm
echo Display Gamma:              %gamma_ipart%.%gamma_fpart%

for %%A in (
    basic_parameter_string
    supported_features_string
    chroma_coordinates
    valid_timings_string
    standard_timing_string
    dtd_string
    dtd_string_2
    dtd_string_3
    dtd_string_4
) do (
    echo:
    echo ---------------------------
    echo:
    for %%B in (!%%~A!) do echo %%~B
)
exit /b

::------------------------------------------------------------------------------
:: Initializes an array of binary values for their hex equivalents, and an
:: array for true/false values with 0 as false and 1 as true
::
:: Arguments: None
:: Returns:   None
::------------------------------------------------------------------------------
:initConstants
for %%B in (
    "0-0000" "1-0001" "2-0010" "3-0011" "4-0100" "5-0101" "6-0110" "7-0111"
    "8-1000" "9-1001" "A-1010" "B-1011" "C-1100" "D-1101" "E-1110" "F-1111"
) do (
    for /f "tokens=1,2 delims=-" %%C in ("%%~B") do set "byte_map[%%~C]=%%~D"
)

:: Think I can get away with only numbers and capital letters?
for %%B in (
    "01000001-A" "01000010-B" "01000011-C" "01000100-D" "01000101-E"
    "01000110-F" "01000111-G" "01001000-H" "01001001-I" "01001010-J"
    "01001011-K" "01001100-L" "01001101-M" "01001110-N" "01001111-O"
    "01010000-P" "01010001-Q" "01010010-R" "01010011-S" "01010100-T"
    "01010101-U" "01010110-V" "01010111-W" "01011000-X" "01011001-Y"
    "01011010-Z" "00110000-0" "00110001-1" "00110010-2" "00110011-3"
    "00110100-4" "00110101-5" "00110110-6" "00110111-7" "00111000-8"
    "00111001-9" "00100000- "
) do (
    for /f "tokens=1,2 delims=-" %%C in ("%%~B") do set "ascii[%%~C]=%%~D"
)

set "tf[0]=False"
set "tf[1]=True "
exit /b

::------------------------------------------------------------------------------
:: Extracts monitor information from WmiMonitorID in WMI via PowerShell and
:: converts it from an array of hex bytes into an ASCII string
::
:: Arguments: %1 - The property to extract from the WmiMonitorID class
::            %2 - The name of the variable to store the output in
:: Returns:   None
::------------------------------------------------------------------------------
:getAsciiWmiValue
set "ps_cmd=[System.Text.Encoding]::ASCII.GetString((Get-WmiObject WmiMonitorID -Namespace root\wmi).%~1)"
for /f "delims=" %%A in ('powershell -command "%ps_cmd%"') do set "%~2=%%~A"
exit /b

::------------------------------------------------------------------------------
:: Extracts the Extended Display Identification Data from regedit after finding
:: the registry key path in WMI. wmic is being wonky so we're using PowerShell.
:: Also, there should probably be some sort of selector for people with multiple
:: monitors, but I'm too lazy to grab my other monitors from my closet to test.
::
:: Arguments: None
:: Returns:   None
::------------------------------------------------------------------------------
:getEdid
set "full_reg_path=HKLM\SYSTEM\CurrentControlSet\Enum"
for /f "delims=" %%A in (
    'powershell -command "(Get-WmiObject WmiMonitorID -Namespace root\wmi).InstanceName"'
) do set "monitor_path=%%~A"
if "!monitor_path!"==" " exit /b 1

set "full_reg_path=%full_reg_path%\%monitor_path:~0,-2%\Device Parameters"
for /f "tokens=3" %%A in ('reg query "%full_reg_path%" /v EDID') do set "edid=%%A"
exit /b

::------------------------------------------------------------------------------
:: Determines the maximum possible resolution for the monitor
::
:: Arguments: None
:: Returns:   None
::------------------------------------------------------------------------------
:getMaxResolution
set "wmic_cmd=wmic path win32_videocontroller get videomodedescription"
for /f "tokens=2,4 delims== " %%A in ('%wmic_cmd% /format:list ^| find "="') do set "max_res=%%Ax%%B"
exit /b

::------------------------------------------------------------------------------
:: Extracts bytes from the EDID array and processes them either forwards or
:: backwards because some genius inexplicably thought that mixed endianness
:: was a good idea
::
:: Arguments: %1 - The first byte to grab
::            %2 - The last byte to grab
::            %3 - The variable to store the data in
::            %4 - The format to convert the data to (hex/int/bin)
:: Returns:   None
::------------------------------------------------------------------------------
:extractData
set /a "min_byte_index=%~1*2", "max_byte_index=%~2*2"
set "loop_order=%max_byte_index%,-2,%min_byte_index%"
if "%~5"=="BE" set "loop_order=%min_byte_index%,2,%max_byte_index%"

for /L %%A in (%loop_order%) do (
    set "current_byte=!edid:~%%A,2!"

    if not "%~4"=="bin" (
        set "%~3=!%~3!!current_byte!"
    ) else (
        call :hexToBin
        set "%~3=!%~3!!binary_value!"
    )
)

if "%~4"=="int" set /a "%~3=0x!%~3!"
exit /b

::------------------------------------------------------------------------------
:: Converts five-bit chunks of bytes 8 and 9 into three ASCII characters. There
:: is a conversion list (https://uefi.org/PNP_ID_List) that I'm not going to
:: add here because it gets updated about once a month.
::
:: Arguments: None
:: Returns:   None
::------------------------------------------------------------------------------
:parseManufacturerId
call :getAsciiText "010!manufacturer_id:~1,5!010!manufacturer_id:~6,5!010!manufacturer_id:~11,5!" pnp_name
exit /b

::------------------------------------------------------------------------------
:: Display either bit depth and video interface for digital inputs, or video
:: white and sync levels, blank-to-black setup expected, separate sync
:: supported, composite sync supported, sync on green supported, and serrated
:: VSync pulse for analog input.
::
:: Arguments: None
:: Returns:   None
::------------------------------------------------------------------------------
:parseBasicParameters
set "basic_parameter_string="

set "basic_input_type=%basic_display:~0,1%"
if "%basic_input_type%"=="0" (
    set "white_sync_levels=%basic_display:~1,2%"

    set "basic_parameter_string="Input Type:                    Analog""
    set "basic_parameter_string=!basic_parameter_string!"White and sync levels:         "
    <nul set /p ".=White and sync levels:         "
    if "!white_sync_levels!"=="00" (
        set "basic_parameter_string=!basic_parameter_string!+0.7 / -0.3 V""
    ) else if "!white_sync_levels!"=="01" (
        set "basic_parameter_string=!basic_parameter_string!+0.714 / -0.286 V""
    ) else if "!white_sync_levels!"=="10" (
        set "basic_parameter_string=!basic_parameter_string!+1.0 / -0.4 V""
    ) else (
        set "basic_parameter_string=!basic_parameter_string!+0.7 / 0 V""
    )

    set "basic_parameter_string=!basic_parameter_string!"Blank-to-black setup expected: !tf[%basic_display:~3,1%]!""
    set "basic_parameter_string=!basic_parameter_string!"Separate sync supported:       !tf[%basic_display:~4,1%]!""
    set "basic_parameter_string=!basic_parameter_string!"Composite sync supported:      !tf[%basic_display:~5,1%]!""
    set "basic_parameter_string=!basic_parameter_string!"Sync on green supported:       !tf[%basic_display:~6,1%]!""
    set "basic_parameter_string=!basic_parameter_string!"Serrated VSync pulse required: !tf[%basic_display:~7,1%]!""
) else (
    set "bit_depth=%basic_display:~1,3%"
    set "video_interface=%basic_display:~4,4%"
    
    set "basic_parameter_string="Input Type:                 Digital" "Bit Depth:                  "
    if "!bit_depth!"=="000" (
        set "basic_parameter_string=!basic_parameter_string!Undefined""
    ) else if "!bit_depth!"=="001" (
        set "basic_parameter_string=!basic_parameter_string!6""
    ) else if "!bit_depth!"=="010" (
        set "basic_parameter_string=!basic_parameter_string!8""
    ) else if "!bit_depth!"=="011" (
        set "basic_parameter_string=!basic_parameter_string!10""
    ) else if "!bit_depth!"=="100" (
        set "basic_parameter_string=!basic_parameter_string!12""
    ) else if "!bit_depth!"=="101" (
        set "basic_parameter_string=!basic_parameter_string!14""
    ) else if "!bit_depth!"=="110" (
        set "basic_parameter_string=!basic_parameter_string!16""
    ) else if "!bit_depth!"=="111" (
        set "basic_parameter_string=!basic_parameter_string!Reserved""
    )

    set "basic_parameter_string=!basic_parameter_string! "Video Interface:            "
    if "!video_interface!"=="0000" (
        set "basic_parameter_string=!basic_parameter_string!Undefined""
    ) else if "!video_interface!"=="0001" (
        set "basic_parameter_string=!basic_parameter_string!DVI""
    ) else if "!video_interface!"=="0010" (
        set "basic_parameter_string=!basic_parameter_string!HDMIa""
    ) else if "!video_interface!"=="0011" (
        set "basic_parameter_string=!basic_parameter_string!HDMIb""
    ) else if "!video_interface!"=="0100" (
        set "basic_parameter_string=!basic_parameter_string!MDDI""
    ) else if "!video_interface!"=="0101" (
        set "basic_parameter_string=!basic_parameter_string!DisplayPort""
    )
)
exit /b

::------------------------------------------------------------------------------
:: Displays the status of various supported features
::
:: Arguments: None
:: Returns:   None
::------------------------------------------------------------------------------
:parseSupportedFeatures
set "supported_formats=%supported_features:~3,2%"

set "supported_features_string="DPMS Standby Supported:     !tf[%supported_features:~0,1%]!""
set "supported_features_string=!supported_features_string! "DPMS Suspend Supported:     !tf[%supported_features:~1,1%]!""
set "supported_features_string=!supported_features_string! "DPMS Active-off Supported:  !tf[%supported_features:~2,1%]!""

set "supported_features_string=!supported_features_string! "Supported Color Formats:    "
if "%basic_input_type%"=="0" (
    if "!supported_formats!"=="00" (
        set "supported_features_string=!supported_features_string!Monochrome""
    ) else if "!supported_formats!"=="01" (
        set "supported_features_string=!supported_features_string!RGB color""
    ) else if "!supported_formats!"=="11" (
        set "supported_features_string=!supported_features_string!Non-RGB color""
    ) else (
        set "supported_features_string=!supported_features_string!Undefined""
    )
) else (
    if "!supported_formats!"=="00" (
        set "supported_features_string=!supported_features_string!RGB 4:4:4""
    ) else if "!supported_formats!"=="01" (
        set "supported_features_string=!supported_features_string!RGB 4:4:4 + YCrCb 4:4:4""
    ) else if "!supported_formats!"=="10" (
        set "supported_features_string=!supported_features_string!RGB 4:4:4 + YCrCb 4:2:2""
    ) else (
        set "supported_features_string=!supported_features_string!RGB 4:4:4 + YCrCb 4:4:4 + YCrCb 4:2:2""
    )
)

set "supported_features_string=!supported_features_string! "Standard sRGB Color Space:  !tf[%supported_features:~5,1%]!""
set "supported_features_string=!supported_features_string! "Native Pixel Format:        !tf[%supported_features:~6,1%]!""
set "supported_features_string=!supported_features_string! "Continuous GTF/CVT Timings: !tf[%supported_features:~7,1%]!""
exit /b

::------------------------------------------------------------------------------
:: Establish chromaticity coordinates according to CIE 1931 xy coordinates
:: 
:: Arguments: None
:: Returns:   None
::------------------------------------------------------------------------------
:getChromaticityCoordinates
set "rx_bin=%rxy_ms_bits:~0,8%%rg_ls_bits:~0,2%"
set "ry_bin=%rxy_ms_bits:~8,8%%rg_ls_bits:~2,2%"
set "gx_bin=%gxy_ms_bits:~0,8%%rg_ls_bits:~4,2%"
set "gy_bin=%gxy_ms_bits:~8,8%%rg_ls_bits:~6,2%"
set "bx_bin=%bxy_ms_bits:~0,8%%bw_ls_bits:~0,2%"
set "by_bin=%bxy_ms_bits:~8,8%%bw_ls_bits:~2,2%"
set "wx_bin=%wxy_ms_bits:~0,8%%bw_ls_bits:~4,2%"
set "wy_bin=%wxy_ms_bits:~8,8%%bw_ls_bits:~6,2%"

call :tenBitBinaryToDecimal %rx_bin% rx_coord
call :tenBitBinaryToDecimal %ry_bin% ry_coord
call :tenBitBinaryToDecimal %gx_bin% gx_coord
call :tenBitBinaryToDecimal %gy_bin% gy_coord
call :tenBitBinaryToDecimal %bx_bin% bx_coord
call :tenBitBinaryToDecimal %by_bin% by_coord
call :tenBitBinaryToDecimal %wx_bin% wx_coord
call :tenBitBinaryToDecimal %wy_bin% wy_coord

set "chroma_coordinates="Chromaticity Coordinates:   R(!rx_coord!,!ry_coord!) G(!gx_coord!,!gy_coord!) B(!bx_coord!,!by_coord!) W(!wx_coord!,!wy_coord!)""
exit /b

::------------------------------------------------------------------------------
:: Convert binary to integer, then divide by 1024 and round to three digits
::
:: Arguments: %1 - The binary string to use in the calculation
::            %2 - The name of the variable to store the output in
:: Returns:   None
::------------------------------------------------------------------------------
:tenBitBinaryToDecimal
call :binToDec "%~1" tenbit_ipart
set /a tenbit_ipart=%tenbit_ipart%*1000/1024
if %tenbit_ipart% LSS 100 (
    set "tenbit_ipart=0%tenbit_ipart%"
) else if %tenbit_ipart% LSS 10 (
    set "tenbit_ipart=00%tenbit_ipart%"
)
set "%~2=0.%tenbit_ipart%"
exit /b

::------------------------------------------------------------------------------
:: Lists supported common timing modes. Note that the variable !timing_3! is
:: not used because it is used for manufacturer-specific display modes.
::
:: Arguments: None
:: Returns:   None
::------------------------------------------------------------------------------
:parseTimingBitmap
set "timings_1[0]=720x400 @ 70 Hz"
set "timings_1[1]=720x400 @ 88 Hz"
set "timings_1[2]=640x480 @ 60 Hz"
set "timings_1[3]=640x480 @ 67 Hz"
set "timings_1[4]=640x480 @ 72 Hz"
set "timings_1[5]=640x480 @ 75 Hz"
set "timings_1[6]=800x600 @ 56 Hz"
set "timings_1[7]=800x600 @ 60 Hz"
set "timings_2[0]=800x600 @ 72 Hz"
set "timings_2[1]=800x600 @ 75 Hz"
set "timings_2[2]=832x624 @ 75 Hz"
set "timings_2[3]=1024x768 @ 87 Hz"
set "timings_2[4]=1024x768 @ 60 Hz"
set "timings_2[5]=1024x768 @ 70 Hz"
set "timings_2[6]=1024x768 @ 75 Hz"
set "timings_2[7]=1280x1024 @ 75 Hz"

set "valid_timings_string="Valid Common Timings:" "
for /L %%A in (0,1,7) do if "!timing_1:~%%A,1!"=="1" set "valid_timings_string=!valid_timings_string! "                            !timings_1[%%A]!""
for /L %%A in (0,1,7) do if "!timing_2:~%%A,1!"=="1" set "valid_timings_string=!valid_timings_string! "                            !timings_2[%%A]!""
exit /b

::------------------------------------------------------------------------------
:: Parses standard timing information, or returns "Unused" if value is "01 01"
::
:: Arguments: None
:: Returns:   None
::------------------------------------------------------------------------------
:parseStandardTiming
set "standard_timing_string="
set "standard_timing_index=1"
for /L %%A in (0,2,14) do (
    set "standard_timing_string=!standard_timing_string! "Standard Timing !standard_timing_index!:          "
    
    if "!standard_timing:~%%A,4!"=="0101" (
        set "standard_timing_string=!standard_timing_string!Undefined""
    ) else (
        set "timing_bytes=!standard_timing:~%%A,4!"
        set /a "timing_x=(!timing_bytes:~0,2!+31)*8"
        if "!timing_bytes:~0,2!"=="00" set "timing_x=Reserved"
        
        call :hexToBin !timing_bytes:~2,2!
        if "!binary_value:~0,2!"=="00" (
            set "timing_aspect_ratio=16:10"
        ) else if "!binary_value:~0,2!"=="01" (
            set "timing_aspect_ratio=4:3"
        ) else if "!binary_value:~0,2!"=="10" (
            set "timing_aspect_ratio=5:4"
        ) else if "!binary_value:~0,2!"=="11" (
            set "timing_aspect_ratio=16:9"
        )
        set /a "vertical_frequency=(!timing_bytes!&31)+60"
        set "standard_timing_string=!standard_timing_string!X Resolution: !timing_x!    Aspect Ratio: !timing_aspect_ratio!    Vertical Frequency: !vertical_frequency!""
    )
    set /a standard_timing_index+=1
)
exit /b

::------------------------------------------------------------------------------
:: Parses detailed timing descriptor information.
::
:: Arguments: %1 - The detailed descriptor data in binary
::            %2 - The name of the variable to store the string in
:: Returns:   None
::------------------------------------------------------------------------------
:parseDetailedTimingDescriptor
set "timing_data=%~1"
if "!timing_data:~0,24!"=="000000000000000000000000" (
    call :parseSecondaryTimingDescriptor "%~2"
    exit /b
)

set "pixel_clock_raw=!timing_data:~8,8!!timing_data:~0,8!"
call :binToDec "!pixel_clock_raw!" pixel_clock_speed
set "pixel_clock_speed=!pixel_clock_speed:~0,-2!.!pixel_clock_speed:~-2!"

call :binToDec "!timing_data:~32,4!!timing_data:~16,8!" horizontal_active_pixels
call :binToDec "!timing_data:~36,4!!timing_data:~24,8!" horizontal_blanking_pixels
call :binToDec "!timing_data:~56,4!!timing_data:~40,8!" vertical_active_pixels
call :binToDec "!timing_data:~60,4!!timing_data:~48,8!" vertical_blanking_pixels

call :binToDec "!timing_data:~88,2!!timing_data:~64,8!" horizontal_front_porch
call :binToDec "!timing_data:~90,2!!timing_data:~72,8!" horizontal_sync_pulse
set /a horizontal_back_porch=horizontal_blanking_pixels-horizontal_front_porch-horizontal_sync_pulse

call :binToDec "!timing_data:~92,2!!timing_data:~80,4!" vertical_front_porch
call :binToDec "!timing_data:~94,2!!timing_data:~84,4!" vertical_sync_pulse
set /a vertical_back_porch=vertical_blanking_pixels-vertical_front_porch-vertical_sync_pulse

call :binToDec "!timing_data:~112,4!!timing_data:~96,8!" horizontal_image_size
call :binToDec "!timing_data:~116,4!!timing_data:~104,8!" vertical_image_size

call :binToDec "!timing_data:~120,8!" horizontal_border_pixels
call :binToDec "!timing_data:~128,8!" vertical_border_pixels

set "features_bitmap=!timing_data:~136,8!"
if "!features_bitmap:~0,1!"=="0" (set "signal_interface=Non-interlaced") else "set signal_interface=Interlaced"
if "!features_bitmap:~1,2!"=="00" (
    set "stereo_mode=None"
) else if "!features_bitmap:~1,2!!features_bitmap:~-1!"=="010" (
    set "stereo_mode=Field sequential, right during stereo sync"
) else if "!features_bitmap:~1,2!!features_bitmap:~-1!"=="100" (
    set "stereo_mode=Field sequential, left during stereo sync"
) else if "!features_bitmap:~1,2!!features_bitmap:~-1!"=="011" (
    set "stereo_mode=2-way interleaved, right image on even lines"
) else if "!features_bitmap:~1,2!!features_bitmap:~-1!"=="101" (
    set "stereo_mode=2-way interleaved, left image on even lines"
) else if "!features_bitmap:~1,2!!features_bitmap:~-1!"=="110" (
    set "stereo_mode=4-way interleaved"
) else if "!features_bitmap:~1,2!!features_bitmap:~-1!"=="111" (
    set "stereo_mode=Side-by-side interleaved"
)

set "max_res=!horizontal_active_pixels!x!vertical_active_pixels!"


set "%~2="Pixel Clock:                !pixel_clock_speed! MHz""
set "%~2=!%~2! "Active Pixels:              !horizontal_active_pixels!x!vertical_active_pixels! (!horizontal_image_size! mm x !vertical_image_size! mm)""
set "%~2=!%~2! "Horizontal Blanking Pixels: !horizontal_blanking_pixels! (Hfront !horizontal_front_porch!, Hsync !horizontal_sync_pulse!, Hback !horizontal_back_porch!)""
set "%~2=!%~2! "Vertical Blanking Pixels:   !vertical_blanking_pixels! (Vfront !vertical_front_porch!, Vsync !vertical_sync_pulse!, Vback !vertical_back_porch!)""
set "%~2=!%~2! "Border:                     !horizontal_border_pixels!x!vertical_border_pixels!""
set "%~2=!%~2! "Signal Interface Type:      !signal_interface!""
set "%~2=!%~2! "Stereo Mode:                !stereo_mode!""

if "!features_bitmap:~3,1!"=="0" (
    set "%~2=!%~2! "Sync:                       Analog""
    set "sync_type=Bipolar Analog Composite"
    set "serration=H-sync during V-sync"
    set "rb_sync_g=Sync on all three video signals"
    if "!features_bitmap:~4,1!"=="0" set "sync_type=Analog Composite"
    if "!features_bitmap:~5,1!"=="0" set "serration=None"
    if "!features_bitmap:~6,1!"=="0" set "rb_sync_g=Sync on green signal only"
    set "%~2=!%~2! "Sync Type:                  !sync_type!""
    set "%~2=!%~2! "Serration:                  !serration!""
    set "%~2=!%~2! "Sync on RGB:                !rb_sync_g!""
) else if "!features_bitmap:~3,2!"=="10" (
    set "%~2=!%~2! "Sync:                       Composite Digital Sync""
    set "serration=H-sync during V-sync"
    set "h_polarity=Positive"
    if "!features_bitmap:~5,1!"=="0" set "serration=None"
    if "!features_bitmap:~6,1!"=="0" set "h_polarity=Negative"
    set "%~2%=!%~2%! "Serration:                  !serration!""
    set "%~2%=!%~2%! "Horizontal Polarity:        !h_polarity!""
) else if "!features_bitmap:~3,2!"=="11" (
    set "%~2=!%~2! "Sync:                       Separate Digital Sync""
    set "v_polarity=Positive"
    set "h_polarity=Positive"
    if "!features_bitmap:~5,1!"=="0" set "v_polarity=Negative"
    if "!features_bitmap:~6,1!"=="0" set "h_polarity=Negative"
    set "%~2=!%~2! "Vertical Polarity           !v_polarity!""
    set "%~2=!%~2! "Horizontal Polarity         !h_polarity!""
)
exit /b

::------------------------------------------------------------------------------
:: Displays information for additional timing descriptors:
:: - FF: monitor serial number (ASCII text)
:: - FE: unspecified (ASCII text)
:: - FD: Monitor range limits
:: - FC: Monitor name (ASCII text)
:: - FB: Additional white point data
:: - FA: Additional standard timing identifiers
:: - F9: Display Color Management
:: - F8: CVT 3-Byte Timing Codes
:: - F7: Additional standard timing 3
:: - 10: Dummy identifier
::
:: Arguments: %1 - The name of the variable to store the output string in
:: Returns:   None
::------------------------------------------------------------------------------
:parseSecondaryTimingDescriptor
set "%~1="

if "!timing_data:~24,8!"=="11111111" (
    call :getAsciiText "!timing_data:~40!" friendly_serial
    set "%~1="Serial Number:              !friendly_serial!""
) else if "!timing_data:~24,8!"=="11111110" (
    call :getAsciiText "!timing_data:~40!" oem_text
    set "%~1="Manufacturer-specific Text: !oem_text!""
) else if "!timing_data:~24,8!"=="11111101" (
    REM FD - Display range limits
    call :monitorRangeLimits "!timing_data:~32!" "%~1"
) else if "!timing_data:~24,8!"=="11111100" (
    call :getAsciiText "!timing_data:~40!" friendly_name
    set "%~1="Monitor Name:               !friendly_name!""
) else if "!timing_data:~24,8!"=="11111011" (
    REM FB - Additional white point descriptor
    if not "!timing_data:~40,8!"=="00000000" call :additionalWhitePointData "!timing_data:~40,40!"
    if not "!timing_data:~80,8!"=="00000000" call :additionalWhitePointData "!timing_data:~80,40!"
) else if "!timing_data:~24,8!"=="11111010" (
    REM FA - Additional standard timings
    call :additionalStandardTimings "!timing_data:~32!" "%~1"
) else if "!timing_data:~24,8!"=="11111001" (
    REM F9 - Color management data descriptor
    call :colorManagementData "!timing_data:~48!" "%~1"
) else if "!timing_data:~24,8!"=="11111000" (
    REM F8 - CVT 3-byte timing codes descriptor
    call :cvt3 "!timing_data:~48!" "%~1"
) else if "!timing_data:~24,8!"=="11110111" (
    REM F7 - Additional standard timings 3
    call :additionalStandardTimings3 "!timing_data:~48,44!" "%~1"
)
exit /b

::------------------------------------------------------------------------------
:: Additional data to describe horizontal and vertical rate ranges
::
:: Arguments: %1 - Bytes 4-17 of the timing descriptor
::                 00: Rate offsets
::                 01: Minimum vertical field rate
::                 02: Maximum vertical field rate
::                 03: Minimum horizontal line rate
::                 04: Maximum horizontal line rate
::                 05: Maximum pixel clock rate in multiples of 10 MHz
::                 06: Extended timing information type
::                 07: Video timing parameters
::            %2 - The name of the variable to store the output string in
:: Returns:   None
::------------------------------------------------------------------------------
:monitorRangeLimits
set "drld=%~1"
set "%~2="

set "h_rate_offset=!drld:~4,2!"
set "v_rate_offset=!drld:~6,2!"
set "extended_timing_info=!drld:~48,4!"

call :binToDec "!drld:~8,8!" v_min_rate
call :binToDec "!drld:~16,8!" v_max_rate
call :binToDec "!drld:~24,8!" h_min_rate
call :binToDec "!drld:~32,8!" h_max_rate
call :binToDec "!drld:~40,8!" max_pixel_clock_rate

if not "!v_rate_offset!"=="00" set /a v_max_rate+=255
if     "!v_rate_offset!"=="11" set /a v_min_rate+=255
if not "!h_rate_offset!"=="00" set /a h_max_rate+=255
if     "!h_rate_offset!"=="11" set /a h_min_rate+=255
set /a max_pixel_clock_rate*=10

if "!extended_timing_info!"=="0000" (
    set "%~2=!%~2! "Extended Timing Type:       Default GTF""
) else if "!extended_timing_info!"=="0001" (
    set "%~2=!%~2! "Extended Timing Type:       No timing information""
) else if "!extended_timing_info!"=="0010" (
    call :binToDec "!drld:~64,8!"             gtf_start
    call :binToDec "!drld:~72,8!"             gtf_c
    call :binToDec "!drld:~88,8!!drld:~80,8!" gtf_m
    call :binToDec "!drld:~96,8!"             gtf_k
    call :binToDec "!drld:~104,8!"            gtf_j

    set /a "gtf_start*=2", "gtf_c/=2", "gtf_j/=2"
    set "%~2=!%~2! "Extended Timing Type:       GTF Secondary Curve (!gtf_start! kHz, C=!gtf_c!, M=!gtf_m!, K=!gtf_k!, J=!gtf_j!^)""
) else if "!extended_timing_info!"=="0100" (
    call :binToDec "!drld:~56,4!" cvt_major_version
    call :binToDec "!drld:~60,4!" cvt_minor_version
    call :binToDec "!drld:~64,6!" clock_precision_excess
    set "max_active_pixels=Unlimited"
    if not "!drld:~72,8!"=="00000000" call :binToDec "!drld:~70,10!" max_active_pixels

    set "%~2=!%~2! "Supported Aspect Ratios:""
    if "!drld:~80,1!"=="1" set "%~2=!%~2! "                            4:3""
    if "!drld:~81,1!"=="1" set "%~2=!%~2! "                            16:9""
    if "!drld:~82,1!"=="1" set "%~2=!%~2! "                            16:10""
    if "!drld:~83,1!"=="1" set "%~2=!%~2! "                            5:4""
    if "!drld:~84,1!"=="1" set "%~2=!%~2! "                            15:9""
    set "aspect_ratio[000]=4:3"
    set "aspect_ratio[001]=16:9"
    set "aspect_ratio[010]=16:10"
    set "aspect_ratio[011]=5:4"
    set "aspect_ratio[100]=15:9"
    set "%~2=!%~2! "Aspect Ratio Preference:    !aspect_ratio[%drld:~88,3%]!""
    set "%~2=!%~2! "CVT-RB Reduced Blanking:    !tf[%drld:~91,1%]!""
    set "%~2=!%~2! "CVT Standard Blanking:      !tf[%drld:~92,1%]!""

    set "%~2=!%~2! "Scaling Support:""
    if "!drld:~96,1!"=="1" set "%~2=!%~2! "                            Horizontal shrink""
    if "!drld:~97,1!"=="1" set "%~2=!%~2! "                            Horizontal stretch""
    if "!drld:~98,1!"=="1" set "%~2=!%~2! "                            Vertical shrink""
    if "!drld:~99,1!"=="1" set "%~2=!%~2! "                            Vertical stretch""

    call :binToDec "!drld:~104,8!" preferred_v_refresh
    set "%~2=!%~2! "Preferred vertical refresh: !preferred_v_refresh!""
)

if defined clock_precision_excess set /a "max_pixel_clock_rate=max_pixel_clock_rate-(clock_precision_excess/4)"
set "%~2=!%~2! "Horizontal Field Rate:      !h_min_rate!-!h_max_rate! Hz""
set "%~2=!%~2! "Vertical Field Rate:        !v_min_rate!-!v_max_rate! Hz""
set "%~2=!%~2! "Max Pixel Clock Rate:       !max_pixel_clock_rate! MHz""
exit /b

::------------------------------------------------------------------------------
:: Gets up to two additional white point descriptors
::
:: Arguments: %1 - Five bytes of the timing descriptor
::                 00: white point index
::                 01: white point XY coordinate least significant bits
::                 02: white point X coordinate most significant bits
::                 03: white point Y coordinate most significant bits
::                 04: white point gamma value
::            %2 - The name of the variable to store the output string in
:: Returns:   None
::------------------------------------------------------------------------------
:additionalWhitePointData
set "wp_data=%~1"

call :binToDec "!wp_data:~0,8!" white_point_index
call :binToDec "!wp_data:~16,8!!wp_data:~12,2!" white_point_x
call :binToDec "!wp_data:~24,8!!wp_data:~14,2!" white_point_y
call :binToDec "!wp_data:~32,8!" white_point_gamma_raw

set /a "wp_gamma_ipart=!white_point_gamma_raw:~0,-2!-1"
set "wp_gamma_fpart=!white_point_gamma_raw:~-2!"

set "%~2=!%~2! "White Point Index:          !white_point_index!""
set "%~2=!%~2! "White Point Coordinates:    !white_point_x!,!white_point_y!""
set "%~2=!%~2! "White Point Gamma:          !wp_gamma_ipart!.!wp_gamma_fpart!""
exit /b

::------------------------------------------------------------------------------
:: An extension of :parseStandardTiming in case they needed more
::
:: Arguments: %1 - six byte pairs of standard timing information
::                 00: Horizontal addressable pixels
::                 01: Aspect ratio and refresh rate
::            %2 - The name of the variable to store the output string in
:: Returns:   None
::------------------------------------------------------------------------------
:additionalStandardTimings
set "extra_standards=%~1"

set "aspect_ratio[00]=16:10"
set "aspect_ratio[01]=4:3"
set "aspect_ratio[10]=5:4"
set "aspect_ratio[11]=16:9"

for /L %%B in (0,16,128) do (
    call :binToDec "!extra_standards:~%%B,8!" h_addressable_pixels

    if not "!h_addressable_pixels!"=="0" (
        set /a timing_offset=%%~B+8
        for /f %%C in ("!timing_offset!") do set "timing_offset_byte=!extra_standards:~%%~C,8!"
        for /f %%C in ("!timing_offset_byte:~0,2!") do set "image_aspect_ratio=!aspect_ratio[%%~C]!"
        
        set /a h_addressable_pixels=h_addressable_pixels/8-31
        call :binToDec "!timing_offset_byte:~-6!" standard_refresh
        set "%~2=!%~2! "Standard Timing:            !h_addressable_pixels!px, !image_aspect_ratio! AR, !standard_refresh! Hz""
    )
)
exit /b

::------------------------------------------------------------------------------
:: Displays color management data
::
:: Arguments: %1 - Bytes 6-17 of the timing descriptor
::                 00: Red a3 LSB
::                 01: Red a3 MSB
::                 02: Red a2 LSB
::                 03: Red a2 MSB
::                 04: Green a3 LSB
::                 05: Green a3 MSB
::                 06: Green a2 LSB
::                 07: Green a2 MSB
::                 08: Blue a3 LSB
::                 09: Blue a3 MSB
::                 10: Blue a2 LSB
::                 11: Blue a2 MSB
::            %2 - The name of the variable to store the output string in
:: Returns:   None
::------------------------------------------------------------------------------
:colorManagementData
set "color_mgmt_data=%~1"

call :binToDec "!color_mgmt_data:~8,8!!color_mgmt_data:~0,8!" red_a3
call :binToDec "!color_mgmt_data:~24,8!!color_mgmt_data:~16,8!" red_a2
call :binToDec "!color_mgmt_data:~40,8!!color_mgmt_data:~32,8!" green_a3
call :binToDec "!color_mgmt_data:~56,8!!color_mgmt_data:~48,8!" green_a2
call :binToDec "!color_mgmt_data:~72,8!!color_mgmt_data:~64,8!" blue_a3
call :binToDec "!color_mgmt_data:~88,8!!color_mgmt_data:~80,8!" blue_a2

set "%~2=!%~2! "Color Management:           R(!red_a3!,!red_a2!) G(!green_a3!,!green_a2!) B(!blue_a3!,!blue_a2!)""
exit /b

::------------------------------------------------------------------------------
:: Displays applicable 3-byte CVT timing codes based on relatively complex math
::
:: Arguments: %1 - Bytes 6-17 of the timing descriptor
::                 00-02: Timing descriptor #1
::                 03-05: Timing descriptor #2
::                 06-08: Timing descriptor #3
::                 09-11: Timing descriptor #4
::            %2 - The name of the variable to store the output string in
:: Returns:   None
::------------------------------------------------------------------------------
:cvt3
set "cvt3_data=%~1"

set "cvt3_ar[00]=4/3"
set "cvt3_ar[01]=16/9"
set "cvt3_ar[10]=16/10"
set "cvt3_ar[11]=15/9"
set "cvt3_vrate[00]=50 MHz"
set "cvt3_vrate[01]=60 MHz"
set "cvt3_vrate[10]=75 MHz"
set "cvt3_vrate[11]=85 MHz"

for /L %%C in (0,24,96) do (
    set /a "cvt3_index=%%C/8+1"
    set "cvt3_b1=!cvt3_data:~%%~C,8!"
    set /a "offset_1=%%C+8", "offset_2=%%C+16"
    for /f "tokens=1,2" %%D in ("!offset_1! !offset_2!") do (
        set "cvt_b2=!cvt3_data:~%%~D,8!"
        set "cvt_b3=!cvt3_data:~%%~E,8!"
    )

    call :binToDec "!cvt3_b2:~0,4!!cvt3_b1!" addressable_lines
    set /a "vertical_lines=(addressable_lines+1)*2"
    for /f "%%D" in ("!cvt3_b2:~4,2!") do (
        set /a "horizontal_pixels=vertical_lines*!cvt3_ar[%%D]!/8*8"
        set "%~2=!%~2! "CVT 3-byte Timing !cvt3_index!:         !horizontal_pixels!x!vertical_lines!, !cvt3_ar[%%D]:/=:! AR""
    )
    for /f "%%D" in ("!cvt3_b3:~4,2!") do set "%~2=!%~2! "Preferred Vertical Rate:    !cvt3_vrate[%%D]!""
    set "%~2=!%~2! "Valid Vertical Rates:""
    if "!cvt3_b3:~3,1!"=="1" set "%~2=!%~2! "                            50 Hz CVT""
    if "!cvt3_b3:~4,1!"=="1" set "%~2=!%~2! "                            60 Hz CVT""
    if "!cvt3_b3:~5,1!"=="1" set "%~2=!%~2! "                            75 Hz CVT""
    if "!cvt3_b3:~6,1!"=="1" set "%~2=!%~2! "                            85 Hz CVT""
    if "!cvt3_b3:~7,1!"=="1" set "%~2=!%~2! "                            60 Hz CVT reduced blanking""
)
exit /b

::------------------------------------------------------------------------------
:: Displays additional standard timings based on a table lookup
::
:: Arguments: %1 - Bits 6-11 of the timing descriptor
::            %2 - The name of the variable to store the output string in
:: Returns:   None
::------------------------------------------------------------------------------
:additionalStandardTimings3
set "ast=%~1"


set "added_timings[0]=640x350 @ 85 MHz"
set "added_timings[1]=640x400 @ 85 MHz"
set "added_timings[2]=720x400 @ 85 MHz"
set "added_timings[3]=640x480 @ 85 MHz"
set "added_timings[4]=848x480 @ 60 MHz"
set "added_timings[5]=800x600 @ 85 MHz"
set "added_timings[6]=1024x768 @ 85 MHz"
set "added_timings[7]=1152x864 @ 85 MHz"
set "added_timings[8]=1280x768 @ 60 MHz CVT-RB"
set "added_timings[9]=1280x768 @ 60 MHz"
set "added_timings[10]=1280x768 @ 75 MHz"
set "added_timings[11]=1280x768 @ 85 MHz"
set "added_timings[12]=1280x960 @ 60 MHz"
set "added_timings[13]=1280x960 @ 85 MHz"
set "added_timings[14]=1280x1024 @ 60 MHz"
set "added_timings[15]=1280x1024 @ 85 MHz"
set "added_timings[16]=1360x768 @ 60 MHz CVT-RB"
set "added_timings[17]=1360x768 @ 60 MHz"
set "added_timings[18]=1440x900 @ 60 MHz CVT-RB"
set "added_timings[19]=1440x900 @ 75 MHz"
set "added_timings[20]=1440x900 @ 85 MHz"
set "added_timings[21]=1440x1050 @ 60 MHz CVT-RB"
set "added_timings[22]=1440x1050 @ 60 MHz"
set "added_timings[23]=1440x1050 @ 75 MHz"
set "added_timings[24]=1440x1050 @ 85 MHz"
set "added_timings[25]=1680x1050 @ 60 MHz CVT-RB"
set "added_timings[26]=1680x1050 @ 60 MHz"
set "added_timings[27]=1680x1050 @ 75 MHz"
set "added_timings[28]=1680x1050 @ 85 MHz"
set "added_timings[29]=1680x1200 @ 60 MHz"
set "added_timings[30]=1680x1200 @ 65 MHz"
set "added_timings[31]=1680x1200 @ 70 MHz"
set "added_timings[32]=1680x1200 @ 75 MHz"
set "added_timings[33]=1680x1200 @ 85 MHz"
set "added_timings[34]=1792x1344 @ 60 MHz"
set "added_timings[35]=1792x1344 @ 75 MHz"
set "added_timings[36]=1856x1392 @ 60 MHz"
set "added_timings[37]=1856x1392 @ 75 MHz"
set "added_timings[38]=1920x1200 @ 60 MHz CVT-RB"
set "added_timings[39]=1920x1200 @ 60 MHz"
set "added_timings[40]=1920x1200 @ 75 MHz"
set "added_timings[41]=1920x1200 @ 85 MHz"
set "added_timings[42]=1920x1440 @ 60 MHz"
set "added_timings[43]=1920x1440 @ 75 MHz"

set "%~2=!%~2! "Valid Additional Timings:""
for /L %%B in (0,1,43) do if "!ast:~%%~B,1!"=="1" set "%~2=!%~2! "                            !added_timings[%%B]!""
exit /b

::------------------------------------------------------------------------------
:: Converts binary to ASCII values via a lookup table because using the usual
:: %==exitCodeAscii% trick will be exhaustingly slow
::
:: Arguments: %1 - The binary string to parse
::            %2 - The variable to store the value in
:: Returns:   None
::------------------------------------------------------------------------------
:getAsciiText
set "binary_data=%~1"
set "ascii_string="
for /L %%B in (0,8,96) do (
    for /f %%C in ("!binary_data:~%%~B,8!") do (
        set "ascii_string=!ascii_string!!ascii[%%~C]!"
    )
)
set "%~2=!ascii_string!"
exit /b

::------------------------------------------------------------------------------
:: Converts hexadecimal to binary one digit at a time via a lookup table
::
:: Arguments: None
:: Returns:   None
::------------------------------------------------------------------------------
:hexToBin
set "binary_value="
for /L %%B in (0,1,1) do (
    set "byte_half=!current_byte:~%%B,1!"
    for /f "delims=" %%C in ("!byte_half!") do (
        set "binary_value=!binary_value!!byte_map[%%~C]!"
    )
)
exit /b

::------------------------------------------------------------------------------
:: Converts binary to decimal and returns the result
:: https://stackoverflow.com/a/30697239
::
:: Arguments: %1 - The binary string to process
::            %2 - The variable to store the decimal value in
:: Returns:   None
::------------------------------------------------------------------------------
:binToDec
set "bin=00000000000000000000000000000000%~1"
set "bin=%bin:~-32%"
set "dec="

for /L %%A in (1,1,32) do (
    set /a "dec=(dec<<1)|!bin:~0,1!"
    set "bin=!bin:~1!"
)
if "%~2" neq "" set "%~2=%dec%"
exit /b