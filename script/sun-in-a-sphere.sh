#!/bin/bash

# Skript for downloading 360° images from https://stereo-ssc.nascom.nasa.gov/browse_sphere/
# and process them to a movie and project to a sphere
#
# The processed images are meant to be used and are tested with a laserbeamer and  a 180° fish eye lens. Correction of color refraction is done.
#
# Configuration file sias.cfg contains various adjustable settings and must be present to run the script.

readonly conf="sun-in-a-sphere.conf"
readonly URL="https://stereo-ssc.nascom.nasa.gov/browse_sphere/"

setup() {
    #go to current dir
    cd "$(dirname "$0")"

    #parse strings to date
    timeframe_start=$(get_date_from_str $timeframe_start)
    timeframe_end=$(get_date_from_str $timeframe_end)

    #test mode
    if [ $test_mode = true ]; then
        test_folder=sun_in_a_sphere_test
        mkdir -p $test_folder
        cd $test_folder
    
    else
        #create worker directory
        mkdir $pics_folder
        cd $pics_folder

    fi

}

#debug console output
debugging() {
    set -x
}

#enable logging
logging() {
    mkdir -p ./logs
    scriptname=$(echo $(basename "$0") | cut -f 1 -d '.')
    logfile="../logs/$(date +"%y-%m-%d-%H%M")_$scriptname.log"

    log() {
        echo "$1" >> $logfile
    }
}

config() {
    val=$(grep -E "^$1=" $conf 2>/dev/null || echo "$1=DEFAULT" | head -n 1 | cut -d '=' -f 2-)

    if [[ $val == DEFAULT ]]
    then
        case $1 in
            movie_name)
                echo -n movie_name=sun_in_a_sphere
                ;;
            timeframe_start)
                echo -n timeframe_start=2012-09-01
                ;;
            timeframe_end)
                echo -n timeframe_end=2012-11-01
                ;;
            wavelength)
                echo -n wavelength=304
                ;;
            contrast)
                echo -n contrast=60%
                ;;
            offset)
                echo -n offset=5
                ;;
            test_mode)
                echo -n test_mode=true
                ;;
            parallel)
                echo -n parallel=false
                ;;
            rotate)
                echo -n rotate=true
                ;;
            clean_afterwards)
                echo -n clean_afterwards=true
                ;;
            pics_folder)
                echo -n pics_folder=sun_in_a_sphere_images
                ;;
            debug)
                echo debug=false
                ;;
            dl)
                echo dl=true
                ;;
        esac
    else
        echo -n $val
    fi
}

init_config() {
    config_values="$(config movie_name)
        $(config timeframe_start)
        $(config timeframe_end)
        $(config wavelength)
        $(config contrast)
        $(config offset)
        $(config test_mode)
        $(config parallel)
        $(config rotate)
        $(config clean_afterwards)
        $(config pics_folder)
        $(config debug)
        $(config dl)"
    eval $config_values

    if [ $parallel = false -a ! -f ./$conf ]; then
        echo $"

        Sun In A Sphere

        ****************************************************************************************************

        No configuration file (sun-in-a-sphere.conf) could be found. 

        Do you wish to continue with the (recommended) default settings?

        Be aware that it takes some time. Running it over night is recommended. Get some sleep.

        ****************************************************************************************************
        
        Settings:
        
        $config_values"
        select yn in "Yes" "No"; do
            case $yn in
                Yes ) break;;
                No ) exit;;
            esac
        done
    fi
}

get_date_from_str() {
    date -j -f "%Y-%m-%d" "$1" "+%s"
}

format_time(){
    echo $(printf '%dh:%dm:%ds\n' $(($1/3600)) $(($1%3600/60)) $(($1%60)))
}

process_image() {
    # if [ -f $1 ]; then
        log "processing file $path$1"

        local img=$(echo $(basename $1) | cut -f 1 -d '.')
        local ext=$(echo $(basename $1) | cut -f 2 -d '.')    

        local dimensions=$(identify -format "%[fx:w]x%[fx:h]" $1)
        local h=$(echo $dimensions | cut -f 2 -d 'x')
        local w=$(echo $dimensions | cut -f 1 -d 'x')

        #get brighness to detect images with missing data
        local brightness=$(convert $1 -colorspace Gray -format "%[fx:quantumrange*image.mean]" info:)
        local brightness_int="$(echo $brightness | cut -f 1 -d '.')"

        #filter out images brightness not in range 30000-40000 (containing missing data)
        if [ $brightness_int -gt 30000 -a $brightness_int -lt 40000 ]; then
            local cmd="convert ./$1 "
            local cmd+=$(color_correction)

            #transformed image file name
            local trans_file="trans_"$1""

            # if [ ! -f $trans_file ]; then
                #transform azimuthal equal distance and rotate
            local cmd+=$(polar_projection $2)
            local cmd+=$(color_correction)
            # fi 
            local cmd+="$trans_file"
        
            #execute image processing command
            eval $"$cmd"
        fi 
    # fi
} 

color_correction() {
    echo $"\\( -page +0+$offset -clone 0 -background none -flatten -channel R -separate \\) \\( -clone 0 -channel G -separate \\) \\( -clone 0 -channel B -separate \\) -delete 0 -channel red,green,blue -combine "
}

polar_projection() {
    local angle=$1
    echo "-virtual-pixel Black -distort Polar 0 -distort SRT $angle -level 0%,$contrast,0.5 "
}

clean_up() {
    if [ $test_mode = false ]; then
        #remove pics folder
        cd .. && rm -r $pics_folder
        log "deleted temp pics folder"
    else
        rm ./$test_image
    fi
}

download() {
    #loop through days in time range and download the images (async)
    dl_i=$timeframe_start
    while [ "$dl_i" -le "$timeframe_end" ]; do
        dl_year=$(date -j -f "%s" $dl_i "+%Y")
        dl_month=$(date -j -f "%s" $dl_i "+%m")
        dl_day=$(date -j -f "%s" $dl_i "+%d")

        dl_path=$URL$dl_year/$dl_month/$dl_day/$wavelength/

        #get all files current one day (=resource); run in background
        wget -q -r -nc -nd -l 1 -A jpg $dl_path &
            
        dl_i=$(($dl_i+86400))
    done
}

image_processing() {
    #init rotation variable
    local rotation_angle=0

     #loop through days in time range and process images
    ip_i=$timeframe_start
    while [ "$ip_i" -le "$timeframe_end" ]; do
        ip_year=$(date -j -f "%s" $ip_i "+%Y")
        ip_month=$(date -j -f "%s" $ip_i "+%m")
        ip_day=$(date -j -f "%s" $ip_i "+%d")

        ip_path=$URL$ip_year/$ip_month/$ip_day/$wavelength/

        #get all file names from html
        files=$(wget -q -O - $ip_path |   grep -o '<a href=['"'"'"][^"'"'"']*['"'"'"]' |   sed -e 's/^<a href=["'"'"']//' -e 's/["'"'"']$//' | grep jpg)
        for ((index=0; index < ${#files[@]}; index++)); do
            # #some headstart, as file test/read check below results in artifacts in the first image
            # if [ $(ls -1 | wc -l) -eq 3 ]
                # FIXME? overall jobs
                # start 4 jobs only
                # while [ $(jobs -r | wc -l) -ge 4 ] ; do sleep 1 ; done
                # run in background
                # (   
                    echo ${files[index+1]}
                    #wait for file to be downloaded and process_image
                    # while true ;do 
                    #     #check if next file exists and process current file (works better than test/read currrent)
                    #     if [ -f ${files[index+1]} ] ; then
                    #         #enable output
                    #         process_image ${files[index]} $rotation_angle
                    #         break
                    #     fi
                    # done
                # ) &

                if [ "$rotate" = true ]; then
                    local rotation_angle=$(($rotation_angle+1))
                fi
        done
        ip_i=$(($ip_i+86400))
    done    
}

run() {
    if [ $test_mode = false ]; then

        # set +x
        
        if [ "$dl" = true ]; then
            log "starting download $day.$month.$year"
            #run downloading job
            # dl_job="download "$@""
            download "$@"
        fi

        image_processing "$@"
        
        # # run image processing job
        # ip_job="image_processing "$@""

        # export -f image_processing
        # export -f download

        # # eval $dl_job

        # #FIXME dl optional
        # parallel download image_processing :::
        
        wait
        #FIXME
        #remainder of downloads 
        rm ./robots.txt.tmp 

        mencoder "mf://trans_*.jpg" -o "../$movie_name.avi" -speed 0.5 -really-quiet -ovc lavc -lavcopts vcodec=mjpeg

    else
        #test mode (single image processing)
        test_image_path=""$URL"2012/10/19/304/"
        test_image="20121019_005615_304.jpg"
        if [ ! -f $test_image ]; then
            wget -q $test_image_path$test_image
        fi

        process_image $test_image        
    fi 

    if [ "$clean_afterwards" = true ]; then
        clean_up
    fi
}

open_projection() {
    #set output file
    if [ $test_mode = true ]; then
        echo $(ls -la .)
        output="./trans_$test_image"
        output_type="Image"
    else
        output="./$movie_name.avi"
        output_type="Video"
    fi

    if [ -f $output ]; then
        #get platform uname
        plattform=$(uname)

        #open output
        case $plattform in 
            Linux)
                xdg_open $output
                ;;
            Darwin)
                open $output
                ;;
        esac
    else
        echo "$output_type could not be created. See log file for more infos or enable debug mode and run again to find out."
    fi
}

main() {

    #time tracking
    start=`date +%s`
    logging "$@"

    #initialize configuration
    init_config "$@"

    if [ "$debug" = true ]; then
        debugging "$@"
    fi

    setup "$@"
    run "$@"

    end=`date +%s`
    runtime=$((end-start))
    echo "Sun in a Sphere terminated in $(format_time $runtime)"

    open_projection "$@"

    #abort async dl's too when interrupted (ctrl-c)
    trap "pkill -P $$" SIGINT
}
main "$@"


# #!/bin/bash
# function finish {
#   # Your cleanup code here
# }
# trap finish EXIT



