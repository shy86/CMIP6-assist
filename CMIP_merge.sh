#!/bin/bash

# Define a function that processes each file
handler() {
  IFS=' ' read p f <<<$1

  dir=$(gawk -F_ "{print $FMT}" <<<$p)
  dir="$OUTDIR/$dir"
  mkdir -p $dir

  n=$(tr -cd ' ' <<<$f | wc -c)

  if [ $n == 0 ]; then
    out="$dir/${f##*/}"
    echo $out

    if [[ "$OVR"=="No" && -e $out ]]; then
      return 1
    fi

    cp $f $out

  else
    tm=$(grep -P "(?<=[_-])\d{4,8}" -o <<<$f | sort | sed -n '1p;$p' | paste -sd '-')
    out="$dir/$p$tm.nc"
    echo $out

    if [[ -e $out ]]; then
      if [[ "$OVR"=="Yes" ]]; then
        rm $out
      else
        return 1
      fi
    fi

    cmd=$(sed "s|{INFILE}|$f|" <<<$CMD)
    eval "$cmd $out"
  fi
}

# 1. Check commands installed
for c in "cdo" "gawk"; do
  command -v $c >/dev/null 2>&1 || MIS=$([[ -z $MIS ]] && echo "$c" || echo "$MIS, $c")
done

if [[ ! -z $MIS ]]; then
  echo "$MIS not installed, please install first."
  exit 1
fi

# 2. Get the input and output directories
clear

read -p "[#>] Please enter the input folder: " INDIR
# INDIR=/mnt/z/CMIP6_data/CMIP6_monthly/cmip6_tasmax_mon/hist-aer
# OUTDIR=/mnt/i/Research/HW_thesis/test
FILES=$(find "$INDIR" -type f -name "*.nc") || exit 1
GRP=$(gawk 'match($0, /([a-zA-Z0-9-]+_){6}/) {
    key=substr($0, RSTART, RLENGTH)
    res[key] = key in res ? res[key]" "$0 : res[key]=$0
}
END {
  for (key in res) {print key, res[key]}
}
' <<<"$FILES")
# [ wc -l <<<"$FILES" -eq wc -l <<<"$GRP" ]  && echo "There are equal number of input and output files, it seems that no file merge."

# 3. Get outdir
read -p "[#>] Please enter the output folder: " OUTDIR
OUTDIR=${OUTDIR%/}

# 4. Set outdir component
clear

META="Variable_Frequency_Source_Experiment_Variant_Grid"
SMP=$(basename $(head -1 <<<"$FILES"))
echo "-------------------------------------------------"
echo "$META"
echo "-------------------------------------------------"
# echo "Variable_Frequency_Source_Experiment_Variant_Grid"
echo "|   1   |    2    |   3  |     4    |   5   | 6 |"
echo -e "\nFor example, $SMP:"
echo "1/2/4      =>      OUTDIR/$(gawk -F_ '{print $1"/"$2"/"$4}' <<<$SMP)/*.nc"
echo "/1/2/4     =>      OUTDIR/$(gawk -F_ '{print $1"/"$2"/"$4}' <<<$SMP)/*.nc"
echo "1-2/3/     =>      OUTDIR/$(gawk -F_ '{print $1"-"$2"/"$3}' <<<$SMP)/*.nc"
echo "12_4       =>      OUTDIR/$(gawk -F_ '{print $1$2"_"$4}' <<<$SMP)/*.nc"
echo "/          =>      OUTDIR/*.nc"
echo -e "Only [1-6_-/] are accepted\n"

while true; do
  read -p "[#>] Please enter the output directory structure (Default: 1/2/4): " FMT
  [[ -z $FMT ]] && FMT="1/2/4" || FMT=${FMT// /}

  [[ ${FMT##*[!1-6/_-]*} && ${FMT##*//*} ]] && break
  echo "Invalid type"
done
FMT=$(sed 's/[1-6]/$&/g;s/[/_-]\+/"&"/g' <<<$FMT)

# 5. Additional operations
clear

read -p "[#>] Additional operations pass to each file (sep by space) : " ADDON
if [ -z "${ADDON}" ]; then
  CMD="cdo --no_history -f nc4 -z zip_1 -mergetime {INFILE}"
else
  ADDON=$(sed 's/-\?\([^ ]\+\)\( \?\)/,-\1/g' <<<$ADDON)
  CMD="cdo --no_history -f nc4 -z zip_1 -mergetime -apply$ADDON [ {INFILE} ]"
fi

# 6. Define run mode
echo -e "\n1) Sequential\n2) Parallel\n3) Quit"
while true; do
  read -p "[#>] Select run mode (Default: Sequential): " OPT

  case ${OPT,,} in
  "" | sequential | 1)
    OPT="Sequential"
    break
    ;;

  parallel | 2)
    OPT="Parallel"
    command -v parallel >/dev/null 2>&1 || {
      echo "parallel not installed, please install first." >&2
      exit 1
    }

    while true; do
      read -p "[#>] Set parallel threads number: " P

      if [[ "$P" =~ ^[1-9][0-9]*$ ]]; then
        break
      else
        echo "Must be a positive integer"
      fi
    done
    break
    ;;

  quit | 3)
    echo "Quit"
    exit 1
    ;;
  *)
    echo -e "Invalid selection, please try again\n"
    ;;
  esac
done

# 7. Whether overwrite
while true; do
  read -p "[#>] If the file exists, whether to overwrite (Y/n)" OVR
  # OVR=${OVR:-Y}

  case ${OVR,,} in
  yes | y)
    OVR="Yes"
    break
    ;;
  no | n)
    OVR="No"
    break
    ;;
  esac
done

# 8. Print summary
clear

echo "------- Summary -------"
echo "Input  Folder:        $INDIR"
echo "Output Folder:        $OUTDIR"
echo "Input  Files Number:  $(wc -l <<<"$FILES")"
echo "Output Files Number:  $(wc -l <<<"$GRP")"
echo "Output Structure:     OUTDIR/$(gawk -F_ "{print $FMT}" <<<$META)/*.nc (e.g., $OUTDIR/$(gawk -F_ "{print $FMT}" <<<$SMP)/*.nc)"
echo "Operation:            $CMD {OUTFILE}"
echo "Run Mode:             $OPT $P"
echo -e "Overwrite:            $OVR\n"

while true; do
  read -p "[#>] Confirm (Y/n): " CFM
  # CFM=${CFM:-Y}

  case ${CFM,,} in
  yes | y)
    break
    ;;
  no | n)
    exit 1
    ;;
  esac
done

# 8. run
echo -e "\n"
if [ "$OPT" = "Parallel" ]; then
  export -f handler
  export OUTDIR CMD FMT OVR
  parallel --progress -j $P handler {} <<<"$GRP"
else
  RED='\033[0;31m'
  NC='\033[0m'
  I=0

  echo "$GRP" | while read LINE; do
    ((I++))
    echo -en "$RED$(date +'%H:%M:%S') [$I/$(wc -l <<<"$GRP")] ${NC}"
    handler "$LINE"
  done
fi
