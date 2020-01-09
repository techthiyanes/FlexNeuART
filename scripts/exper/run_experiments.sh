#!/bin/bash
. scripts/common_proc.sh
. scripts/config.sh


checkVarNonEmpty "COLLECT_ROOT"
checkVarNonEmpty "DEFAULT_NUM_RAND_RESTART"
checkVarNonEmpty "DEFAULT_NUM_TREES"
checkVarNonEmpty "DEFAULT_METRIC_TYPE"
checkVarNonEmpty "CAND_PROV_LUCENE"
checkVarNonEmpty "EXPER_SUBDIR"

checkVarNonEmpty "TEST_SET_PARAM"
checkVarNonEmpty "EXPER_SUBDIR_PARAM"

numRandRestart=$DEFAULT_NUM_RAND_RESTART
numTrees=$DEFAULT_NUM_TREES
metricType=$DEFAULT_METRIC_TYPE
""
useLMARTParam=""

checkVarNonEmpty "DEFAULT_TRAIN_CAND_QTY"
checkVarNonEmpty "DEFAULT_TEST_CAND_QTY_LIST"

trainCandQty=$DEFAULT_TRAIN_CAND_QTY
testCandQtyList=$DEFAULT_TEST_CAND_QTY_LIST


globalParams=""

useSeparateShell=1
parallelExperQty=1
numCpuCores=""

threadQty=""

defaultTestSet=""
defaultTrainSet=""

function usage {
  msg=$1
  echo $msg
  cat <<EOF
Usage: <collection> <feature desc. file in subdir $EXPER_DESC_SUBDIR> [additional options]
Additional options:
  -max_num_query_test   max. # of test queries
  -num_cpu_cores        # of available CPU cores
  -thread_qty           # of threads
  -parallel_exper_qty   # of experiments to run in parallel (default $parallelExperQty)
  -delete_trec_runs     delete TREC run files
  -no_separate_shell    use this for debug purposes only
  -reuse_feat           reuse previously generated features
  -test_part            default test set, e.g., dev1
  -train_part           default train set, e.g., train
  -train_cand_qty       # of candidates for training (default $trainCandQty)
  -test_cand_qty_list   a comma-separate list of # candidates for testing (default $testCandQtyList)
  -metric_type          evaluation metric (default $metricType)
  -skip_eval            skip/disable evaluation, just produce TREC runs
  -test_model_results   additionally test model performance on the training set
  -max_num_query_train  max. # of training queries
  -debug_print          print every executed command
EOF
}

SET GLOBAL PARAMS

while [ $# -ne 0 ] ; do
  OPT_VALUE=""
  OPT=""
  echo $1|grep "^-" >/dev/null
  if [ $? = 0 ] ; then
    OPT_NAME="$1"
    OPT_VALUE="$2"
    if [ "$OPT_NAME" = "-reuse_feat" ] ; then
      globalParams+=" $OPT_NAME"
      # option without an argument shift by 1
      shift 1
    elif [ "$OPT_NAME" = "-debug_print" ] ; then
      globalParams+=" $OPT_NAME"
      set -x
      # option without an argument shift by 1
      shift 1
    elif [ "$OPT_NAME" = "-test_model_results" ] ; then
      globalParams+=" $OPT_NAME"
      # option without an argument shift by 1
      shift 1
    elif [ "$OPT_NAME" = "-delete_trec_runs" ] ; then
      globalParams+=" $OPT_NAME"
      # option without an argument shift by 1
      shift 1
    elif [ "$OPT_NAME" = "-skip_eval" ] ; then
      globalParams+=" $OPT_NAME"
      # option without an argument shift by 1
      shift 1
    elif [ "$OPT_NAME" = "-no_separate_shell" ] ; then
      useSeparateShell=0
      # option without an argument shift by 1
      shift 1
    elif [ "$OPT_NAME" = "-h" -o "$OPT_NAME" = "-help" ] ; then
      usage
      exit 1
    else
      OPT_VALUE="$2"
      OPT="$1 $2"
      if [ "$OPT_VALUE" = "" ] ; then
        echo "Option $OPT_NAME requires an argument." >&2
        exit 1
      fi
      shift 2 # option with an argument: shift by two
      case $OPT_NAME in
        -thread_qty)
          threadQty=$OPT_VALUE
          globalParams+=" $OPT"
          ;;
        -num_cpu_cores)
          numCpuCores=$OPT_VALUE
          globalParams+=" $OPT"
          ;;
        -train_cand_qty)
          globalParams+=" $OPT"
          ;;
        -test_cand_qty_list)
          globalParams+=" $OPT"
          ;;
        -parallel_exper_qty)
          globalParams+=" $OPT"
          ;;
        -metric_type)
          globalParams+=" $OPT"
          ;;
        -max_num_query_train)
          globalParams+=" $OPT"
          ;;
        -max_num_query_test)
          globalParams+=" $OPT"
          ;;
        -test_part)
          defaultTestSet=$OPT_VALUE
          ;;
        -train_part)
          defaultTrainSet=$OPT_VALUE
          ;;
        *)
          echo "Invalid option: $OPT_NAME" >&2
          exit 1
          ;;
      esac
    fi
  else
    POS_ARGS=(${POS_ARGS[*]} $1)
    shift 1
  fi
done


collect=${POS_ARGS[0]}
if [ "$collect" = "" ] ; then
  usage "Specify a collection, e.g., squad (1st arg)"
  exit 1
fi


collectRoot="$COLLECT_ROOT/$collect"

featDescFile=${POS_ARGS[1]}
if [ "$featDescFile" = "" ] ; then
  usage "Specify a feature description file *RELATIVE* to $collectRoot (2d arg)"
  exit 1
fi

if [ "$numCpuCores" = "" ] ; then
  numCpuCores=`getNumCpuCores`
fi
if [ "$numCpuCores" = "" ] ; then
  usage "Cannot guess # of CPU cores, please, provide # of CPUs cores"
  exit 1
fi

if [ "$threadQty" = "" ] ; then
  threadQty=$(($numCpuCores/$parallelExperQty))
  if [ "$threadQty" = "0" ] ; then
    threadQty=1
  fi
fi

echo "The number of CPU cores:      $numCpuCores"
echo "The number of || experiments: $parallelExperQty"
echo "The number of threads:        $threadQty"


checkVarNonEmpty "featDescFile"
experDescPath=$collectRoot/$featDescFile
if [ ! -f "$experDescPath" ] ; then
  echo "Not a file '$experDescPath'"
  exit 1
fi

nTotal=0
nRunning=0

echo "$SEP_DEBUG_LINE"

echo "Experiment descriptor file:                                 $experDescPath"
echo "Default test set:                                           $defaultTestSet"
echo "Number of parallel experiments:                             $parallelExperQty"
echo "Number of threads in feature extractors/query applications: $threadQty"

echo "$SEP_DEBUG_LINE"

tmpConf=`mktemp`

# Mapping between JSON field names and corresponding script parameters
jsonParamMap=(\
  cand_prov_add_conf candProvAddConfParam \
  cand_prov_uri candProvURI \
  num_rand_restart numRandRestart \
  train_part trainPart \
  extr_type extrType \
  extr_type_interm  extrTypeInterm \
  model_interm modelInterm \
  model_final modelFinal \
  train_cand_qty trainCandQty \
  cand_prov candProv \
  cand_qty candQty \
  test_cand_qty_list testCandQtyList \
  num_trees numTrees \
)

# Some locations are always relative to the collection root
adjustLocForParams=(extrType extrTypeInterm modelInterm modelFinal)

childPIDs=()
nrun=0
nfail=0
for ((ivar=1;;++ivar)) ; do

  parsedConfig=`scripts/exper/parse_exper_conf.py "$experDescPath" "$((ivar-1))"`

  if [ "$parsedConfig" = "" ] ; then
    echo "Failed to get entry $ivar from experiment config $experDescPath"
    exit 1
  elif [ "$parsedConfig" = "#OOR" ] ; then # out of range
    ivar=-100 # this will terminate the loop
  else
    testSet=`grepStrForVal $TEST_SET_PARAM "$parsedConfig"`
    experSubdir=`grepStrForVal $EXPER_SUBDIR_PARAM "$parsedConfig"`

    if [ "$testSet" = "" ] ; then
      echo "Missing $TEST_SET_PARAM config # $ivar"
      exit 1
    fi
    if [ "$experSubdir" = "" ] ; then
      echo "Missing $EXPER_SUBDIR_PARAM config # $ivar"
      exit 1
    fi

    # Each experiment should run in its own sub-directory
    getExperDirBase=$(getExperDirBase "$COLLECTION_ROOT/$EXPER_SUBDIR" "$testSet" "$experSubdir")

    singleConfParams=""

    for ((i=0;i<${#jsonParamMap[*]};i+=2)) ; do
      paramName=${jsonParamMap[$i]}
      jsonParamName=${jsonParamMap[$(($i+1))]}
      val=`grepStrForVal "$jsonParamName"  "$parsedConfig"`
      for adjParamName in ${adjustLocForParams[*]} ; do
        if [ "$adjParamName" = "$jsonParamName" ] ; then
          val="$collectRoot/$val"
        fi
      done
      # Overriding the value of the default training set
      if [ "$paramName" = "train_set" -a "$val" = "" ] ; then
        val="$defaultTrainSet"
      fi
      if [ "$val" != "" ] ; then
        singleConfParams+=" -${paramName} \"$val\""
      fi
    done

# Don't quote $globalParams or any other "*Param*
  cmd=`cat <<EOF
        scripts/exper/run_one_feature_exper.sh \
            "$collect" \
            "$getExperDirBase" \
            "$testSet" \
            $globalParams $singleConfParams &> $getExperDir/exper.log
EOF
`
    if [ "$useSeparateShell" = "1" ] ; then
      bash -c "$cmd" &

      pid=$!
      childPIDs+=($pid)
      echo "Started a process $pid, working dir: $getExperDir"
      nRunning=$(($nRunning+1))
      nrun=$(($nrun+1))
    else
      echo "Starting a process, working dir: $getExperDir"
      bash -c "$cmd"
    fi

  fi
  if [ "$nRunning" -ge $parallelExperQty ] ; then
    waitChildren ${childPIDs[*]}
    childPIDs=()
    nRunning=0
  fi
done
waitChildren ${childPIDs[*]}
echo "$SEP_DEBUG_LINE"
echo "$nrun experiments executed"
echo "$nfail experiments failed"
if [ "$nfail" -gt "0" ] ; then
  echo "Check the log in working directories!!!"
fi
echo "$SEP_DEBUG_LINE"
rm "$tmpConf"

