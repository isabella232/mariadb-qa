#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# The name of this script (pquery-prep-red.sh) was kept short so as to not clog directory listings - it's full name would be ./pquery-prepare-reducer.sh

# To aid with correct bug to testcase generation for pquery trials, this script creates a local run script for reducer and sets #VARMOD#.
# This handles crashes/asserts/Valgrind issues for the moment only. Could be expanded later for other cases, and to handle more unforseen situations.
# Query correctness: data (output) correctness (QC DC) trial handling was also added 11 May 2016

# Improvement ideas
# - It would be better if failing queries were added like this; 3x{query_from_err_log,query_from_core},3{SELECT 1},3{SELECT SLEEP(5)} instead of 3{query_from_core},3{query_from_err_log},3{SELECT 1},3{SELECT SLEEP(5)}

# User configurable variables
VALGRIND_OVERRIDE=0    # If set to 1, Valgrind issues are handled as if they were a crash (core dump required)
SCAN_FOR_NEW_BUGS=1    # If set to 1, all generated reducders will scan for new issues while reducing!

# Internal variables
SCRIPT_PWD=$(cd "`dirname $0`" && pwd)
WORKD_PWD=$PWD
REDUCER="${SCRIPT_PWD}/reducer.sh"

# Disable history substitution and avoid  -bash: !: event not found  like errors
set +H

# Sanity checks
if [ ! -r ${SCRIPT_PWD}/new_text_string.sh ]; then
  echo "Assert: ${SCRIPT_PWD}/new_text_string.sh not readable by this script!"
  exit 1
fi
if [ ${SCAN_FOR_NEW_BUGS} -eq 1 -a ! -r ${SCRIPT_PWD}/known_bugs.strings ]; then
  echo "Assert: SCAN_FOR_NEW_BUGS=1, yet ${SCRIPT_PWD}/known_bugs.strings was not found?"
  exit 1
fi

# Check if this is a pxc run
if [ "$(grep 'PXC Mode:' ./pquery-run.log 2> /dev/null | sed 's|^.*PXC Mode[: \t]*||' )" == "TRUE" ]; then
  PXC=1
else
  PXC=0
fi

# Check if this is a group replication run
if [ "$(grep 'Group Replication Mode:' ./pquery-run.log 2> /dev/null | sed 's|^.*Group Replication Mode[: \t]*||')" == "TRUE" ]; then
  GRP_RPL=1
else
  GRP_RPL=0
fi

# Check if this an automated (pquery-reach.sh) run
if [ "$1" == "reach" ]; then
  REACH=1  # Minimal output, and no 2x enter required
else
  REACH=0  # Normal output
fi

# Check if this is a query correctness run
QC=0
if [ $(ls */*.out */*.sql 2>/dev/null | egrep --binary-files=text -oi "innodb|rocksdb|tokudb|myisam|memory|csv|ndb|merge|aria|sequence|mrg_myisam" | wc -l) -gt 0 ]; then
  if [ "$1" != "noqc" ]; then  # Even though query correctness trials were found, process this run as a crash/assert run only
    QC=1
  fi
fi

# Variable checks
if [ ! -r ${REDUCER} ]; then
  echo "Assert: this script could not read reducer.sh at ${REDUCER} - please set REDUCER variable inside the script correctly."
  exit 1
fi

# Current location checks
if [ `ls */*thread-[1-9]*.sql 2>/dev/null | wc -l` -gt 0 ]; then
  echo -e "** NOTE ** Multi-threaded trials (./*/*thread-[1-9]*.sql) were found. For multi-threaded trials, now the 'total sql' file containing all executed queries (as randomly generated by pquery-run.sh prior to pquery's execution) is used. Reducer scripts will be generated as per normal (with the relevant multi-threaded options already set), and they will be pointed to these (i.e. one file per trial) SQL testcases. Failing sql from the coredump and the error log will be auto-added (interleaved multile times) to ensure better reproducibility. A new feature has also been added to reducer.sh, allowing it to reduce multi-threaded testcases multi-threadely using pquery --threads=x, each time with a reduced original (and still random) sql file. If the bug reproduces, the testcase is reduced further and so on. This will thus still end up with a very small testcase, which can be then used in combination with pquery --threads=x.\n"
  MULTI=1
fi
if [ ${QC} -eq 0 ]; then
  if [ `ls */*thread-0.sql 2>/dev/null | wc -l` -eq 0 ]; then
    echo "Assert: there were 0 pquery sql files found (./*/*thread-0.sql) in subdirectories of the current directory. Terminating."
    exit 1
  fi
else
  echo "Query correctness trials found! Only processing query correctness results. To process crashes/asserts pass 'noqc' as the first option to this script (pquery-prep-red.sh noqc)"
fi

WSREP_OPTION_CHECK=0
if [ `ls */WSREP_PROVIDER_OPT* 2>/dev/null | wc -l` -gt 0 ];then
  WSREP_OPTION_CHECK=1
  WSREP_PROVIDER_OPTIONS=
fi

MYEXTRA=             # Note that MYEXTRA as obtained from any trial's MYEXTRA file (i.e. ./{trialnr}/MYEXTRA) - ref below - includes MYSAFE but not MYINIT, which is read in separately from a ./{trialnr}/MYINIT file. MYINIT cannot be joined to MYEXTRA as MYEXTRA cannot be passed in full to mysqld --initialize as that may cause mysqld initialization to fail
VALGRIND_CHECK=0

if [ `ls ./*/MYEXTRA* 2>/dev/null | wc -l` -eq 0 ]; then 
  echo "Assert: No MYEXTRA files for trials (./*/MYEXTRA*) were found. This should not be the case. Please check what is wrong."
  exit 1
fi

#Check MS/PS pquery binary
#PQUERY_BIN="`grep 'pquery Binary' ./pquery-run.log | sed 's|^.*pquery Binary[: \t]*||' | head -n1`"    # < swap back to this one once old runs are gone (upd: maybe not. Issues.)
if [ -r *pquery*.conf* ]; then
  SEARCH_STR_BIN="*pquery*.conf*"
else
  SEARCH_STR_BIN="*pquery*.sh"  # For backward compatibility. Remove October 2017 or later.
fi
PQUERY_BIN=$(echo "$(grep -ihm1 "^[ \t]*PQUERY_BIN=" ${SEARCH_STR_BIN} | sed 's|[ \t]*#.*$||;s|PQUERY_BIN=||')" | sed "s|\${SCRIPT_PWD}|${SCRIPT_PWD}|" | head -n1)
echo "pquery binary used: ${PQUERY_BIN}"

if [ "${PQUERY_BIN}" == "" ]; then
  echo "Assert! pquery binary used could not be auto-determined. Check script around \$PQUERY_BIN initialization."
  exit 1
fi

check_if_startup_failure(){  # This function may not be 100% compatible with multi-threaded (MULTI=1) yet (though an attempt was made with the [0-9] regex, ref the MULTI one above which has [1-9] but here we're checking for any startup failure and that would only happen if startup_failure_thread-0.sql is present. Then again, pquery-run.sh may not rename a file correctly to something like startup_failure_thread-{threadnr}.sql - to be verified also. < some TODO's. This function works fine for single thread runs. Multi-thread runs untested. May or may not work as described. Feel free to improve and then remove this note.
  STARTUP_ISSUE=0
  echo "* Checking if this trial had a mysqld startup failure"
  if [ `ls ${TRIAL}/*startup_failure_thread-[0-9]*.sql 2>/dev/null | wc -l` -gt 0 ]; then
    echo "  > This trial had a mysqld startup failure, the trial's reducer will be set to reduce as such (using REDUCE_STARTUP_ISSUES=1)"
    STARTUP_ISSUE=1
  else
    echo "  > This trial is not marked by a mysqld startup failure"
  fi
}

extract_queries_core(){
  echo "* Obtaining quer(y)(ies) from the trial's coredump (core: ${CORE})"
  . ${SCRIPT_PWD}/pquery-failing-sql.sh ${TRIAL} 1  # The leading dot and space (and note it should not read ./) is signficant - it means "source" this script, ref bash manual for more information
  if [ "${MULTI}" == "1" ]; then
    CORE_FAILURE_COUNT=`cat ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing | wc -l`
    echo "  > $[ $CORE_FAILURE_COUNT ] quer(y)(ies) added with interleave sql function to the SQL trace"
  else
    for i in {1..3}; do
      BEFORESIZE=`cat ${INPUTFILE} | wc -l`
      cat ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing >> ${INPUTFILE}
      AFTERSIZE=`cat ${INPUTFILE} | wc -l`
    done
    echo "  > $[ $AFTERSIZE - $BEFORESIZE ] quer(y)(ies) added 3x to the SQL trace"
    rm -Rf ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing
  fi
}

extract_queries_error_log(){
  # Extract the "Query:" crashed query from the error log (making sure we have the 'Query:' one at the end)
  echo "* Obtaining quer(y)(ies) from the trial's mysqld error log (if any)"
  . ${SCRIPT_PWD}/pquery-failing-sql.sh ${TRIAL} 2
  if [ "${MULTI}" == "1" ]; then
    FAILING_SQL_COUNT=`cat ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing | wc -l`
    if [ "${CORE_FAILURE_COUNT}" == "" ]; then CORE_FAILURE_COUNT=0; fi
    echo "  > $[ ${FAILING_SQL_COUNT} - ${CORE_FAILURE_COUNT} ] quer(y)(ies) will be added with interleave sql function to the SQL trace"
  else
    for i in {1..3}; do
      BEFORESIZE=`cat ${INPUTFILE} | wc -l`
      cat ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing >> ${INPUTFILE}
      AFTERSIZE=`cat ${INPUTFILE} | wc -l`
    done
    echo "  > $[ $AFTERSIZE - $BEFORESIZE ] quer(y)(ies) added 3x to the SQL trace"
    rm -Rf ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing
  fi
}

add_select_ones_to_trace(){  # Improve issue reproducibility by adding 3x SELECT 1; to the sql trace
  echo "* Adding additional 'SELECT 1;' queries to improve issue reproducibility"
  if [ ! -f ${INPUTFILE} ]; then touch ${INPUTFILE}; fi
  for i in {1..3}; do
    echo "SELECT 1;" >> ${INPUTFILE}
  done
  echo "  > 3 'SELECT 1;' queries to the SQL trace"
}

add_select_sleep_to_trace(){  # Improve issue reproducibility by adding 2x SELECT SLEEP(5); to the sql trace
  echo "* Adding additional 'SELECT SLEEP(5);' queries to improve issue reproducibility"
  if [ ! -f ${INPUTFILE} ]; then touch ${INPUTFILE}; fi
  for i in {1..3}; do
    echo "SELECT SLEEP(5);" >> ${INPUTFILE}
  done
  echo "  > 2 'SELECT SLEEP(5);' queries added to the SQL trace"
}

remove_non_sql_from_trace(){
  echo "* Removing any non-SQL lines (diagnostic output from pquery) to improve issue reproducibility"
  mv ${INPUTFILE} ${INPUTFILE}.filter1
  egrep --binary-files=text -v "Last [0-9]+ consecutive queries all failed" ${INPUTFILE}.filter1 > ${INPUTFILE}
  rm ${INPUTFILE}.filter1
}

auto_interleave_failing_sql(){
  # sql interleave function based on actual input file size
  INPUTLINECOUNT=`cat ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.backup | wc -l`
  FAILING_SQL_COUNT=`cat ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing | wc -l`
  if [ $FAILING_SQL_COUNT -ge 10 ]; then
    if [ $INPUTLINECOUNT -le 100 ]; then
      sed -i "0~5 r ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing" ${INPUTFILE}
    elif [ $INPUTLINECOUNT -le 500 ];then
      sed -i "0~25 r ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing" ${INPUTFILE}
    elif [ $INPUTLINECOUNT -le 1000 ];then
      sed -i "0~50 r ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing" ${INPUTFILE}
    else
      sed -i "0~75 r ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing" ${INPUTFILE}
    fi
  else
    if [ $INPUTLINECOUNT -le 100 ]; then
      sed -i "0~3 r ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing" ${INPUTFILE}
    elif [ $INPUTLINECOUNT -le 500 ];then
      sed -i "0~15 r ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing" ${INPUTFILE}
    elif [ $INPUTLINECOUNT -le 1000 ];then
      sed -i "0~35 r ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing" ${INPUTFILE}
    else
      sed -i "0~50 r ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing" ${INPUTFILE}
    fi
  fi
}

generate_reducer_script(){
  if [ "${BASE}" == "" ]; then
    echo "Assert! \$BASE is empty at start of generate_reducer_script()"
    exit 1
  fi
  USE_NEW_TEXT_STRING=1  # Set to 1 (on) until proven otherwise, i.e. when MODE!=3
  if [ -r ${BASE}/lib/mysql/plugin/ha_tokudb.so ]; then
    DISABLE_TOKUDB_AUTOLOAD=0
  else
    DISABLE_TOKUDB_AUTOLOAD=1
  fi
  if [ ${QC} -eq 0 ]; then
    PQUERY_EXTRA_OPTIONS="s|ZERO0|ZERO0|"
    PQUERYOPT_CLEANUP="s|ZERO0|ZERO0|"
  else
    PQUERY_EXTRA_OPTIONS="0,/#VARMOD#/s|#VARMOD#|PQUERY_EXTRA_OPTIONS=\"--log-all-queries --log-failed-queries --no-shuffle --log-query-statistics --log-client-output --log-query-number\"\n#VARMOD#|"
    PQUERYOPT_CLEANUP="0,/^[ \t]*PQUERY_EXTRA_OPTIONS[ \t]*=.*$/s|^[ \t]*PQUERY_EXTRA_OPTIONS[ \t]*=.*$|#PQUERY_EXTRA_OPTIONS=<set_below_in_machine_variables_section>|"
  fi
  if [ "$TEXT" == "" -o "$TEXT" == "my_print_stacktrace" -o "$TEXT" == "0" -o "$TEXT" == "NULL" ]; then  # Too general strings, or no TEXT found, use MODE=4
    MODE=4
    USE_NEW_TEXT_STRING=0
    TEXT_CLEANUP="s|ZERO0|ZERO0|"  # A zero-effect change dummy (de-duplicates #VARMOD# code below)
    TEXT_STRING1="s|ZERO0|ZERO0|"
    TEXT_STRING2="s|ZERO0|ZERO0|"
  else  # Bug-specific TEXT string found, use MODE=3 to let reducer.sh reduce for that specific string
    if [[ $VALGRIND_CHECK -eq 1 ]]; then
      USE_NEW_TEXT_STRING=0  # As here new_text_string.sh will not be used, but valgrind_string.sh
      MODE=1
    else
      if [ ${QC} -eq 0 ]; then
        MODE=3
      else
        USE_NEW_TEXT_STRING=0  # As here we're doing QC (Query correctness testing), not crash testing
        MODE=2
      fi
    fi
    TEXT_CLEANUP="0,/^[ \t]*TEXT[ \t]*=.*$/s|^[ \t]*TEXT[ \t]*=.*$|#TEXT=<set_below_in_machine_variables_section>|"
    TEXT_STRING1="0,/#VARMOD#/s:#VARMOD#:# IMPORTANT NOTE; Leave the 3 spaces before TEXT on the next line; pquery-results.sh uses these\n#VARMOD#:"
    if [[ "${TEXT}" = *":"* ]]; then
      if [[ "${TEXT}" = *"|"* ]]; then
        if [[ "${TEXT}" = *"/"* ]]; then
          if [[ "${TEXT}" = *"_"* ]]; then
            if [[ "${TEXT}" = *"-"* ]]; then
              echo "Assert (#1)! No suitable sed seperator found. TEXT (${TEXT}) contains all of the possibilities, add more!"
            else
              if [ ${QC} -eq 0 ]; then
                TEXT="$(echo "$TEXT"|sed -e "s-&-\\\\\\&-g")"  # Escape '&' correctly
                TEXT_STRING2="0,/#VARMOD#/s-#VARMOD#-   TEXT=\"${TEXT}\"\n#VARMOD#-"
              else
                TEXT="$(echo "$TEXT"|sed -e "s-|-\\\\\\\|-g")"
                TEXT_STRING2="0,/#VARMOD#/s-#VARMOD#-   TEXT=\"^${TEXT}\$\"\n#VARMOD#-"
              fi
            fi
          else
            if [ ${QC} -eq 0 ]; then
              TEXT="$(echo "$TEXT"|sed -e "s_&_\\\\\\&_g")"  # Escape '&' correctly
              TEXT_STRING2="0,/#VARMOD#/s_#VARMOD#_   TEXT=\"${TEXT}\"\n#VARMOD#_"
            else
              TEXT="$(echo "$TEXT"|sed -e "s_|_\\\\\\\|_g")"
              TEXT_STRING2="0,/#VARMOD#/s_#VARMOD#_   TEXT=\"^${TEXT}\$\"\n#VARMOD#_"
            fi
          fi
        else
          if [ ${QC} -eq 0 ]; then
            TEXT="$(echo "$TEXT"|sed -e "s/&/\\\\\\&/g")"  # Escape '&' correctly
            TEXT_STRING2="0,/#VARMOD#/s/#VARMOD#/   TEXT=\"${TEXT}\"\n#VARMOD#/"
          else
            TEXT="$(echo "$TEXT"|sed -e "s/|/\\\\\\\|/g")"
            TEXT_STRING2="0,/#VARMOD#/s/#VARMOD#/   TEXT=\"^${TEXT}\$\"\n#VARMOD#/"
          fi
        fi
      else
        if [ ${QC} -eq 0 ]; then
          TEXT="$(echo "$TEXT"|sed -e "s|&|\\\\\\&|g")"  # Escape '&' correctly
          TEXT_STRING2="0,/#VARMOD#/s|#VARMOD#|   TEXT=\"${TEXT}\"\n#VARMOD#|"
        else
          # TODO: check if something was missed here, or is there no swap needed for "|" perhaps?
          TEXT_STRING2="0,/#VARMOD#/s|#VARMOD#|   TEXT=\"^${TEXT}\$\"\n#VARMOD#|"
        fi
      fi
    else
      if [ ${QC} -eq 0 ]; then
        TEXT="$(echo "$TEXT"|sed -e "s:&:\\\\\\&:g")"  # Escape '&' correctly
        TEXT_STRING2="0,/#VARMOD#/s:#VARMOD#:   TEXT=\"${TEXT}\"\n#VARMOD#:"
      else
        TEXT="$(echo "$TEXT"|sed -e "s:|:\\\\\\\|:g")"
        TEXT_STRING2="0,/#VARMOD#/s:#VARMOD#:   TEXT=\"^${TEXT}\$\"\n#VARMOD#:"
      fi
    fi
  fi
  if [ "$MYEXTRA" == "" ]; then  # Empty MYEXTRA string
    MYEXTRA_CLEANUP="s|ZERO0|ZERO0|"
    MYEXTRA_STRING1="s|ZERO0|ZERO0|"  # Idem as above
  else  # MYEXTRA specifically set
    MYEXTRA_CLEANUP="0,/^[ \t]*MYEXTRA[ \t]*=.*$/s|^[ \t]*MYEXTRA[ \t]*=.*$|#MYEXTRA=<set_below_in_machine_variables_section>|"
    if [[ "${MYEXTRA}" = *":"* ]]; then
      if [[ "${MYEXTRA}" = *"|"* ]]; then
        if [[ "${MYEXTRA}" = *"!"* ]]; then
          echo "Assert! No suitable sed seperator found. MYEXTRA (${MYEXTRA}) contains all of the possibilities, add more!"
        else
          MYEXTRA_STRING1="0,/#VARMOD#/s!#VARMOD#!MYEXTRA=\"${MYEXTRA}\"\n#VARMOD#!"
        fi
      else
        MYEXTRA_STRING1="0,/#VARMOD#/s|#VARMOD#|MYEXTRA=\"${MYEXTRA}\"\n#VARMOD#|"
      fi
    else
      MYEXTRA_STRING1="0,/#VARMOD#/s:#VARMOD#:MYEXTRA=\"${MYEXTRA}\"\n#VARMOD#:"
    fi
  fi
  if [ "$MYINIT" == "" ]; then  # Empty MYINIT string
    MYINIT_CLEANUP="s|ZERO0|ZERO0|"
    MYINIT_STRING1="s|ZERO0|ZERO0|"  # Idem as above
  else  # MYINIT specifically set
    MYINIT_CLEANUP="0,/^[ \t]*MYINIT[ \t]*=.*$/s|^[ \t]*MYINIT[ \t]*=.*$|#MYINIT=<set_below_in_machine_variables_section>|"
    if [[ "${MYINIT}" = *":"* ]]; then
      if [[ "${MYINIT}" = *"|"* ]]; then
        if [[ "${MYINIT}" = *"!"* ]]; then
          echo "Assert! No suitable sed seperator found. MYINIT (${MYINIT}) contains all of the possibilities, add more!"
        else
          MYINIT_STRING1="0,/#VARMOD#/s!#VARMOD#!MYINIT=\"${MYINIT}\"\n#VARMOD#!"
        fi
      else
        MYINIT_STRING1="0,/#VARMOD#/s|#VARMOD#|MYINIT=\"${MYINIT}\"\n#VARMOD#|"
      fi
    else
      MYINIT_STRING1="0,/#VARMOD#/s:#VARMOD#:MYINIT=\"${MYINIT}\"\n#VARMOD#:"
    fi
  fi
  if [ "$WSREP_PROVIDER_OPTIONS" == "" ]; then  # Empty MYEXTRA string
    WSREP_OPT_CLEANUP="s|ZERO0|ZERO0|"
    WSREP_OPT_STRING="s|ZERO0|ZERO0|"  # Idem as above
  else
    WSREP_OPT_CLEANUP="0,/^[ \t]*WSREP_PROVIDER_OPTIONS[ \t]*=.*$/s|^[ \t]*WSREP_PROVIDER_OPTIONS[ \t]*=.*$|#WSREP_PROVIDER_OPTIONS=<set_below_in_machine_variables_section>|"
    WSREP_OPT_STRING="0,/#VARMOD#/s:#VARMOD#:WSREP_PROVIDER_OPTIONS=\"${WSREP_PROVIDER_OPTIONS}\"\n#VARMOD#:"
  fi
  if [ "$MULTI" != "1" ]; then  # Not a multi-threaded pquery run
    MULTI_CLEANUP="s|ZERO0|ZERO0|"  # Idem as above
    MULTI_CLEANUP2="s|ZERO0|ZERO0|"
    MULTI_CLEANUP3="s|ZERO0|ZERO0|"
    MULTI_STRING1="s|ZERO0|ZERO0|"
    MULTI_STRING2="s|ZERO0|ZERO0|"
    MULTI_STRING3="s|ZERO0|ZERO0|"
  else  # Multi-threaded pquery run
    MULTI_CLEANUP1="0,/^[ \t]*PQUERY_MULTI[ \t]*=.*$/s|^[ \t]*PQUERY_MULTI[ \t]*=.*$|#PQUERY_MULTI=<set_below_in_machine_variables_section>|"
    MULTI_CLEANUP2="0,/^[ \t]*FORCE_SKIPV[ \t]*=.*$/s|^[ \t]*FORCE_SKIPV[ \t]*=.*$|#FORCE_SKIPV=<set_below_in_machine_variables_section>|"
    MULTI_CLEANUP3="0,/^[ \t]*FORCE_SPORADIC[ \t]*=.*$/s|^[ \t]*FORCE_SPORADIC[ \t]*=.*$|#FORCE_SPORADIC=<set_below_in_machine_variables_section>|"
    MULTI_STRING1="0,/#VARMOD#/s:#VARMOD#:PQUERY_MULTI=1\n#VARMOD#:"
    MULTI_STRING2="0,/#VARMOD#/s:#VARMOD#:FORCE_SKIPV=1\n#VARMOD#:"
    MULTI_STRING3="0,/#VARMOD#/s:#VARMOD#:FORCE_SPORADIC=1\n#VARMOD#:"
  fi
  if [[ ${PXC} -eq 1 ]]; then
    PXC_CLEANUP1="0,/^[ \t]*PXC_MOD[ \t]*=.*$/s|^[ \t]*PXC_MOD[ \t]*=.*$|#PXC_MOD=<set_below_in_machine_variables_section>|"
    PXC_STRING1="0,/#VARMOD#/s:#VARMOD#:PXC_MOD=1\n#VARMOD#:"
  else
    PXC_CLEANUP1="s|ZERO0|ZERO0|"  # Idem as above
    PXC_STRING1="s|ZERO0|ZERO0|"
  fi
  if [[ ${GRP_RPL} -eq 1 ]]; then
    GRP_RPL_CLEANUP1="0,/^[ \t]*GRP_RPL_MOD[ \t]*=.*$/s|^[ \t]*GRP_RPL_MOD[ \t]*=.*$|#GRP_RPL_MOD=<set_below_in_machine_variables_section>|"
    GRP_RPL_STRING1="0,/#VARMOD#/s:#VARMOD#:GRP_RPL_MOD=1\n#VARMOD#:"
  else
    GRP_RPL_CLEANUP1="s|ZERO0|ZERO0|"  # Idem as above
    GRP_RPL_STRING1="s|ZERO0|ZERO0|"
  fi
  if [[ ${QC} -eq 0 ]]; then
    REDUCER_FILENAME=reducer${OUTFILE}.sh
    QC_STRING1="s|ZERO0|ZERO0|"
    QC_STRING2="s|ZERO0|ZERO0|"
    QC_STRING3="s|ZERO0|ZERO0|"
    QC_STRING4="s|ZERO0|ZERO0|"
  else
    REDUCER_FILENAME=qcreducer${OUTFILE}.sh
    QC_STRING1="s|CURRENTLINE=2|CURRENTLINE=5|g"
    QC_STRING2="s|REALLINE=2|REALLINE=5|g"
    # Ref [*], temporarily disabled
    # QC_STRING3="0,/#VARMOD#/s:#VARMOD#:QCTEXT=\"${QCTEXT}\"\n#VARMOD#:"
    QC_STRING3="0,/#VARMOD#/s:#VARMOD#:#QCTEXT=\"${QCTEXT}\"\n#VARMOD#:"
    QC_STRING4="s|SKIPSTAGEABOVE=9|SKIPSTAGEABOVE=3|"
  fi
  if [[ ${STARTUP_ISSUE} -eq 0 ]]; then
    SI_CLEANUP1="s|ZERO0|ZERO0|"
    SI_STRING1="s|ZERO0|ZERO0|"
  else
    SI_CLEANUP1="0,/^[ \t]*REDUCE_STARTUP_ISSUES[ \t]*=.*$/s|^[ \t]*REDUCE_STARTUP_ISSUES[ \t]*=.*$|#REDUCE_STARTUP_ISSUES=<set_below_in_machine_variables_section>|"
    SI_STRING1="0,/#VARMOD#/s:#VARMOD#:REDUCE_STARTUP_ISSUES=1\n#VARMOD#:"
  fi
  cat ${REDUCER} \
   | sed -e "0,/^[ \t]*INPUTFILE[ \t]*=.*$/s|^[ \t]*INPUTFILE[ \t]*=.*$|#INPUTFILE=<set_below_in_machine_variables_section>|" \
   | sed -e "0,/^[ \t]*MODE[ \t]*=.*$/s|^[ \t]*MODE[ \t]*=.*$|#MODE=<set_below_in_machine_variables_section>|" \
   | sed -e "0,/^[ \t]*DISABLE_TOKUDB_AUTOLOAD[ \t]*=.*$/s|^[ \t]*DISABLE_TOKUDB_AUTOLOAD[ \t]*=.*$|#DISABLE_TOKUDB_AUTOLOAD=<set_below_in_machine_variables_section>|" \
   | sed -e "0,/^[ \t]*TEXT_STRING_LOC[ \t]*=.*$/s|^[ \t]*TEXT_STRING_LOC[ \t]*=.*$|#TEXT_STRING_LOC=<set_below_in_machine_variables_section>|" \
   | sed -e "0,/^[ \t]*USE_NEW_TEXT_STRING[ \t]*=.*$/s|^[ \t]*USE_NEW_TEXT_STRING[ \t]*=.*$|#USE_NEW_TEXT_STRING=<set_below_in_machine_variables_section>|" \
   | sed -e "0,/^[ \t]*SCAN_FOR_NEW_BUGS[ \t]*=.*$/s|^[ \t]*SCAN_FOR_NEW_BUGS[ \t]*=.*$|#SCAN_FOR_NEW_BUGS=<set_below_in_machine_variables_section>|" \
   | sed -e "0,/^[ \t]*KNOWN_BUGS[ \t]*=.*$/s|^[ \t]*KNOWN_BUGS[ \t]*=.*$|#KNOWN_BUGS=<set_below_in_machine_variables_section>|" \
   | sed  "0,/^[ \t]*SCRIPT_PWD[ \t]*=.*$/s|^[ \t]*SCRIPT_PWD[ \t]*=.*$|SCRIPT_PWD=${SCRIPT_PWD}|" \
   | sed -e "${PQUERYOPT_CLEANUP}" \
   | sed -e "${MYEXTRA_CLEANUP}" \
   | sed -e "${MYINIT_CLEANUP}" \
   | sed -e "${WSREP_OPT_CLEANUP}" \
   | sed -e "${TEXT_CLEANUP}" \
   | sed -e "${MULTI_CLEANUP1}" \
   | sed -e "${MULTI_CLEANUP2}" \
   | sed -e "${MULTI_CLEANUP3}" \
   | sed -e "0,/^[ \t]*BASEDIR[ \t]*=.*$/s|^[ \t]*BASEDIR[ \t]*=.*$|#BASEDIR=<set_below_in_machine_variables_section>|" \
   | sed -e "0,/^[ \t]*USE_PQUERY[ \t]*=.*$/s|^[ \t]*USE_PQUERY[ \t]*=.*$|#USE_PQUERY=<set_below_in_machine_variables_section>|" \
   | sed -e "0,/^[ \t]*PQUERY_LOC[ \t]*=.*$/s|^[ \t]*PQUERY_LOC[ \t]*=.*$|#PQUERY_LOC=<set_below_in_machine_variables_section>|" \
   | sed -e "${PXC_CLEANUP1}" \
   | sed -e "${GRP_RPL_CLEANUP1}" \
   | sed -e "${SI_CLEANUP1}" \
   | sed -e "${SI_STRING1}" \
   | sed -e "0,/#VARMOD#/s:#VARMOD#:MODE=${MODE}\n#VARMOD#:" \
   | sed -e "0,/#VARMOD#/s:#VARMOD#:DISABLE_TOKUDB_AUTOLOAD=${DISABLE_TOKUDB_AUTOLOAD}\n#VARMOD#:" \
   | sed -e "0,/#VARMOD#/s:#VARMOD#:TEXT_STRING_LOC=\"${SCRIPT_PWD}/new_text_string.sh\"\n#VARMOD#:" \
   | sed -e "0,/#VARMOD#/s:#VARMOD#:USE_NEW_TEXT_STRING=${USE_NEW_TEXT_STRING}\n#VARMOD#:" \
   | sed -e "${TEXT_STRING1}" \
   | sed -e "${TEXT_STRING2}" \
   | sed -e "0,/#VARMOD#/s:#VARMOD#:BASEDIR=\"${BASE}\"\n#VARMOD#:" \
   | sed -e "0,/#VARMOD#/s:#VARMOD#:INPUTFILE=\"${INPUTFILE}\"\n#VARMOD#:" \
   | sed -e "0,/#VARMOD#/s:#VARMOD#:SCAN_FOR_NEW_BUGS=${SCAN_FOR_NEW_BUGS}\n#VARMOD#:" \
   | sed -e "0,/#VARMOD#/s:#VARMOD#:KNOWN_BUGS=\"${SCRIPT_PWD}/known_bugs.strings\"\n#VARMOD#:" \
   | sed -e "${MYEXTRA_STRING1}" \
   | sed -e "${MYINIT_STRING1}" \
   | sed -e "${WSREP_OPT_STRING}" \
   | sed -e "${MULTI_STRING1}" \
   | sed -e "${MULTI_STRING2}" \
   | sed -e "${MULTI_STRING3}" \
   | sed -e "0,/#VARMOD#/s:#VARMOD#:USE_PQUERY=1\n#VARMOD#:" \
   | sed -e "0,/#VARMOD#/s:#VARMOD#:PQUERY_LOC=${PQUERY_BIN}\n#VARMOD#:" \
   | sed -e "${PXC_STRING1}" \
   | sed -e "${GRP_RPL_STRING1}" \
   | sed -e "${QC_STRING1}" \
   | sed -e "${QC_STRING2}" \
   | sed -e "${QC_STRING3}" \
   | sed -e "${QC_STRING4}" \
   | sed -e "${PQUERY_EXTRA_OPTIONS}" \
   > ${REDUCER_FILENAME}
  chmod +x ${REDUCER_FILENAME}
}

# Main pquery results processing
if [ ${QC} -eq 0 ]; then
  if [[ ${PXC} -eq 1 || ${GRP_RPL} -eq 1 ]]; then
    for TRIAL in $(ls ./*/node*/*core* 2>/dev/null | sed 's|./||;s|/.*||' | sort | sort -u); do
      for SUBDIR in `ls -lt ${TRIAL} --time-style="long-iso"  | egrep --binary-files=text '^d' | awk '{print $8}' | tr -dc '0-9\n' | sort`; do
        OUTFILE="${TRIAL}-${SUBDIR}"
        rm -Rf  ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing
        touch ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing
        echo "========== Processing pquery trial ${TRIAL}-${SUBDIR}"
        if [ -r ./reducer${TRIAL}-${SUBDIR}.sh ]; then
          echo "* Reducer for this trial (./reducer${TRIAL}_${SUBDIR}.sh) already exists. Skipping to next trial."
          continue
        fi
        if [ `ls ./${TRIAL}/MYEXTRA 2>/dev/null | wc -l` -gt 0 ]; then
          MYEXTRA=$(cat ./${TRIAL}/MYEXTRA 2>/dev/null)
        else
          echo "Warning: no MYEXTRA file found for trial ${TRIAL} (./${TRIAL}/MYEXTRA). This should not be the case, unless this run ran out of diskspace"
        fi
        MYINIT=$(cat ./${TRIAL}/MYINIT 2>/dev/null)
        if [ ${WSREP_OPTION_CHECK} -eq 1 ]; then
          WSREP_PROVIDER_OPTIONS=$(cat ./${TRIAL}/WSREP_PROVIDER_OPT 2>/dev/null)
        fi
        if [ "${MULTI}" == "1" ]; then
          INPUTFILE=${WORKD_PWD}/${TRIAL}/${TRIAL}.sql
          cp ${INPUTFILE} ${INPUTFILE}.backup
        else
          if [ $(ls -1 ./${TRIAL}/*thread-0.sql 2>/dev/null|wc -l) -gt 1 ]; then
            INPUTFILE=$(ls ./${TRIAL}/node${SUBDIR}*thread-0.sql)
          elif [ -f ./${TRIAL}/*thread-0.sql ] ; then
            INPUTFILE=`ls ./${TRIAL}/*thread-0.sql | sed "s|^[./]\+|/|;s|^|${WORKD_PWD}|"`
          else
            INPUTFILE=${WORKD_PWD}/${TRIAL}/${TRIAL}-${SUBDIR}.sql
          fi
        fi
        BIN=`ls -1 ${WORKD_PWD}/${TRIAL}/node${SUBDIR}/mysqld 2>&1 | head -n1 | grep -v "No such file"`
        if [ ! -r $BIN ]; then
          echo "Assert! mysqld binary '$BIN' could not be read"
          exit 1
        fi
        if [ `ls ./pquery-run.log 2>/dev/null | wc -l` -eq 0 ]; then
          BASE="/sda/Percona-Server-5.6.21-rel70.0-696.Linux.x86_64-debug"  # Should never really happen, but just in case, so that something "is there"? Needs review.
        else
          BASE="`grep 'Basedir:' ./pquery-run.log | sed 's|^.*Basedir[: \t]*||;;s/|.*$//' | tr -d '[[:space:]]'`"
        fi
        CORE=`ls -1 ./${TRIAL}/node${SUBDIR}/*core* 2>&1 | head -n1 | grep -v "No such file"`
        ERRLOG=./${TRIAL}/node${SUBDIR}/node${SUBDIR}.err
        if [ `cat ${INPUTFILE} | wc -l` -ne 0 ]; then
          if [ "$CORE" != "" ]; then
            extract_queries_core
          fi
          if [ "$ERRLOG" != "" ]; then
            extract_queries_error_log
          else
            echo "Assert! Error log at ./${TRIAL}/node${SUBDIR}/error.log could not be read?"
            exit 1
          fi
        fi
        add_select_ones_to_trace
        add_select_sleep_to_trace
        remove_non_sql_from_trace
        # OLD_WAY: TEXT="$(${SCRIPT_PWD}/OLD/text_string.sh ./${TRIAL}/node${SUBDIR}/node${SUBDIR}.err)"
        TEXT="$(cat ./${TRIAL}/node${SUBDIR}/MYBUG | head -n1)"  # TODO: this change needs further testing for cluster/GR. Also, it is likely someting was missed for this in the updated pquery-run.sh: the need to generate a MYBUG file for each node!
        echo "* TEXT variable set to: \"${TEXT}\""
        if [ "${MULTI}" == "1" ]; then
           if [ -s ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing ];then
             auto_interleave_failing_sql
           fi
        fi
        generate_reducer_script
      done
      if [ "${MYEXTRA}" != "" ]; then
        echo "* MYEXTRA variable set to: ${MYEXTRA}"
      fi
      if [ "${WSREP_PROVIDER_OPTIONS}" != "" ]; then
        echo "* WSREP_PROVIDER_OPTIONS variable set to: ${WSREP_PROVIDER_OPTIONS}"
      fi
      if [[ ${VALGRIND_CHECK} -eq 1 ]]; then
        echo "* Valgrind was used for this trial"
      fi
      echo "Trial analysis complete. Reducer created: ${PWD}/reducer${TRIAL}-${SUBDIR}.sh"
    done
  else
    for SQLLOG in $(ls ./*/*thread-0.sql 2>/dev/null); do
      TRIAL=`echo ${SQLLOG} | sed 's|./||;s|/.*||'`
      if [ `ls ./${TRIAL}/MYEXTRA 2>/dev/null | wc -l` -gt 0 ]; then
        MYEXTRA=$(cat ./${TRIAL}/MYEXTRA 2>/dev/null)
      else
        echo "Warning: no MYEXTRA file found for trial ${TRIAL} (./${TRIAL}/MYEXTRA). This should not be the case, unless this run ran out of diskspace"
      fi
      MYINIT=$(cat ./${TRIAL}/MYINIT 2>/dev/null)
      if [ ${PXC} -eq 0 ]; then
        OUTFILE=$TRIAL
        rm -Rf ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing
        touch ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing
        if [ ${REACH} -eq 0 ]; then # Avoid normal output if this is an automated run (REACH=1)
          echo "========== Processing pquery trial $TRIAL"
        fi
        if [ ! -r ./${TRIAL}/start ]; then
          echo "* No ./${TRIAL}/start detected, so this was likely a SAVE_SQL=1, SAVE_TRIALS_WITH_CORE_ONLY=1 trial with no core generated. Skipping to next trial."
          continue
        fi
        if [ -r ./reducer${TRIAL}.sh ]; then
          echo "* Reducer for this trial (./reducer${TRIAL}.sh) already exists. Skipping to next trial."
          continue
        fi
        if [ "${MULTI}" == "1" ]; then
          INPUTFILE=${WORKD_PWD}/${TRIAL}/${TRIAL}.sql
          cp ${INPUTFILE} ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.backup
        else
          INPUTFILE=`echo ${SQLLOG} | sed "s|^[./]\+|/|;s|^|${WORKD_PWD}|"`
        fi
        BIN=$(grep "\/mysqld" ./${TRIAL}/start | head -n1 | sed 's|mysqld .*|mysqld|;s|.* \(.*bin/mysqld\)|\1|')
        if [ "${BIN}" == "" ]; then
          echo "Assert \$BIN is empty for trial $TRIAL, please fix this trial manually"
          continue
        fi
        if [ ! -r "${BIN}" ]; then
          echo "Assert! mysqld binary '${BIN}' could not be read"
          exit 1
        fi
        BASE=`echo ${BIN} | sed 's|/bin/mysqld||'`
        if [ ! -d "${BASE}" ]; then
          echo "Assert! Basedir '${BASE}' does not look to be a directory"
          exit 1
        fi
        CORE=`ls -1 ./${TRIAL}/data/*core* 2>&1 | head -n1 | grep -v "No such file"`
        if [ "$CORE" != "" ]; then
          extract_queries_core
        fi
        ERRLOG=./${TRIAL}/log/master.err
        if [ "$ERRLOG" != "" ]; then
          extract_queries_error_log
        else
          echo "Assert! Error log at ./${TRIAL}/log/master.err could not be read?"
          exit 1
        fi
        add_select_ones_to_trace
        add_select_sleep_to_trace
        remove_non_sql_from_trace
        # Check if this trial was/had a startup failure (which would take priority over anything else) - will be used to set REDUCE_STARTUP_ISSUES=1
        check_if_startup_failure
        VALGRIND_CHECK=0
        VALGRIND_ERRORS_FOUND=0; VALGRIND_CHECK_1=
        if [ -r ./${TRIAL}/VALGRIND -a ${VALGRIND_OVERRIDE} -ne 1 ]; then
          VALGRIND_CHECK=1
          # What follows are 3 different ways of checking if Valgrind issues were seen, mostly to ensure that no Valgrind issues go unseen, especially if log is not complete
          VALGRIND_CHECK_1=$(grep --binary-files=text "==[0-9]\+== ERROR SUMMARY: [0-9]\+ error" ./${TRIAL}/log/master.err | sed 's|.*ERROR SUMMARY: \([0-9]\+\) error.*|\1|')
          if [ "${VALGRIND_CHECK_1}" == "" ]; then VALGRIND_CHECK_1=0; fi
          if [ ${VALGRIND_CHECK_1} -gt 0 ]; then
            VALGRIND_ERRORS_FOUND=1
          fi
          if egrep --binary-files=text -qi "^[ \t]*==[0-9]+[= \t]+[atby]+[ \t]*0x" ./${TRIAL}/log/master.err; then
            VALGRIND_ERRORS_FOUND=1
          fi
          if egrep --binary-files=text -qi "==[0-9]+== ERROR SUMMARY: [1-9]" ./${TRIAL}/log/master.err; then
            VALGRIND_ERRORS_FOUND=1
          fi
          if [ ${VALGRIND_ERRORS_FOUND} -eq 1 ]; then
            TEXT="$(${SCRIPT_PWD}/valgrind_string.sh ./${TRIAL}/log/master.err)"
            if [ "${TEXT}" != "" ]; then
              echo "* Valgrind string detected: '${TEXT}'"
            else
              echo "*** ERROR: No specific Valgrind string was detected in ./${TRIAL}/log/master.err! This may be a bug... Setting TEXT to generic '==    at 0x'"
              TEXT="==    at 0x"
            fi
            # generate a valgrind specific reducer and then reset values if standard crash reducer is needed
            OUTFILE=_val$TRIAL
            generate_reducer_script
            VALGRIND_CHECK=0
            OUTFILE=$TRIAL
          fi
        fi
        # if not a valgrind run process everything, if it is valgrind run only if there's a core
        if [ ! -r ./${TRIAL}/VALGRIND ] || [ -r ./${TRIAL}/VALGRIND -a "$CORE" != "" ]; then
          # OLD_WAY: TEXT="$(${SCRIPT_PWD}/OLD/text_string.sh ./${TRIAL}/log/master.err)"
          TEXT="$(cat ./${TRIAL}/MYBUG)"
          echo "* TEXT variable set to: \"${TEXT}\""
          if [ "${MULTI}" == "1" -a -s ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing ];then
            auto_interleave_failing_sql
          fi
          generate_reducer_script
        fi
      fi
      if [ "${MYEXTRA}" != "" ]; then
        echo "* MYEXTRA variable set to: ${MYEXTRA}"
      fi
      if [ ${VALGRIND_CHECK} -eq 1 ]; then
        echo "* Valgrind was used for this trial"
      fi
    done
  fi
else
  for TRIAL in $(ls ./*/diff.result 2>/dev/null | sed 's|./||;s|/.*||'); do
    BIN=$(grep "\/mysqld" ./${TRIAL}/start | head -n1 | sed 's|mysqld .*|mysqld|;s|.* \(.*bin/mysqld\)|\1|')
    if [ "${BIN}" == "" ]; then
      echo "Assert \$BIN is empty"
      exit 1
    fi
    if [ ! -r "${BIN}" ]; then
      echo "Assert! mysqld binary '${BIN}' could not be read"
      exit 1
    fi
    BASE=`echo ${BIN} | sed 's|/bin/mysqld||'`
    if [ ! -d "${BASE}" ]; then
      echo "Assert! Basedir '${BASE}' does not look to be a directory"
      exit 1
    fi
    TEXT="$(grep --binary-files=text "^[<>]" ./${TRIAL}/diff.result | awk '{print length, $0;}' | sort -nr | head -n1 | sed 's/^[0-9]\+[ \t]\+//')"
    LEFTRIGHT=$(echo ${TEXT} | sed 's/\(^.\).*/\1/')
    TEXT="$(echo ${TEXT} | sed 's/[<>][ \t]\+//')"
    ENGINE=
    FAULT=0
    # Pre-processing all possible sql files to make it suitable for reducer.sh and manual replay - this can be handled in pquery core < TODO
    sed -i "s/;|NOERROR/;#NOERROR/" ${WORKD_PWD}/${TRIAL}/*_thread-0.*.sql
    sed -i "s/;|ERROR/;#ERROR/" ${WORKD_PWD}/${TRIAL}/*_thread-0.*.sql
    if [ "${LEFTRIGHT}" == "<" ]; then
      ENGINE=$(cat ./${TRIAL}/diff.left)
      if [ `ls ./${TRIAL}/MYEXTRA.left 2>/dev/null | wc -l` -gt 0 ]; then
        MYEXTRA=$(cat ./${TRIAL}/MYEXTRA.left 2>/dev/null)
      else
        echo "Warning: no MYEXTRA.left file found for trial ${TRIAL} (./${TRIAL}/MYEXTRA.left). This should not be the case, unless this run ran out of diskspace"
      fi
      MYINIT=$(cat ./${TRIAL}/MYINIT 2>/dev/null)
    elif [ "${LEFTRIGHT}" == ">" ]; then
      ENGINE=$(cat ./${TRIAL}/diff.right)
      if [ `ls ./${TRIAL}/MYEXTRA.right 2>/dev/null | wc -l` -gt 0 ]; then
        MYEXTRA=$(cat ./${TRIAL}/MYEXTRA.right 2>/dev/null)
      else
        echo "Warning: no MYEXTRA.right file found for trial ${TRIAL} (./${TRIAL}/MYEXTRA.right). This should not be the case, unless this run ran out of diskspace"
      fi
      MYINIT=$(cat ./${TRIAL}/MYINIT 2>/dev/null)
    else
      # Possible reasons for this can be: interrupted or crashed trial, ... ???
      echo "Warning! \$LEFTRIGHT != '<' or '>' but '${LEFTRIGHT}' for trial ${TRIAL}! NOTE: qcreducer${TRIAL}.sh will not be complete: renaming to qcreducer${TRIAL}_notcomplete.sh!"
      FAULT=1
    fi
    if [ ${FAULT} -ne 1 ]; then
      QCTEXTLN=$(echo "${TEXT}" | grep --binary-files=text -o "[0-9]*$")
      TEXT="$(echo ${TEXT} | sed "s/#[0-9]*$//")"
      QCTEXT="$(sed -n "${QCTEXTLN},${QCTEXTLN}p" ${WORKD_PWD}/${TRIAL}/*_thread-0.${ENGINE}.sql | grep --binary-files=text -o "#@[0-9]*#")"
    fi
    # Output of the following is too verbose
    #if [ "${MYEXTRA}" != "" ]; then
    #  echo "* MYEXTRA variable set to: ${MYEXTRA}"
    #fi
    INPUTFILE=$(echo ${TRIAL} | sed "s|^|${WORKD_PWD}/|" | sed "s|$|/*_thread-0.${ENGINE}.sql|")
    echo "* Query Correctness: Data Correctness (QC DC) TEXT variable for trial ${TRIAL} set to: \"${TEXT}\""
    # TODO: TEMPORARILY DISABLED THIS; re-review QCTEXT variable functionality later. Also see change at [*]
    #echo "* Query Correctness: Line Identifier (QC LI) QCTEXT variable for trial ${TRIAL} set to: \"${QCTEXT}\""
    OUTFILE=$TRIAL
    generate_reducer_script
    if [ ${FAULT} -eq 1 ]; then
      mv ./qcreducer${TRIAL}.sh ./qcreducer${TRIAL}_notcomplete.sh
    fi
  done
fi

# Process shutdown timeout issues correctly
# * The "grep -H "^MODE=4$" reducer*" ensures that we have only reducers which were not otherwise recognized
# * Checking for a coredump ensures that there was no coredump found in the trial's directory
# * The check for ${MATCHING_TRIAL}/SHUTDOWN_TIMEOUT_ISSUE ensures that the issue was a shutdown issue
# If these 3 all apply, it is safe to change the MODE to =0 and assume that this is a shutdown issue only
for MATCHING_TRIAL in `grep -H "^MODE=4$" reducer* 2>/dev/null | awk '{print $1}' | sed 's|:.*||;s|[^0-9]||g' | sort -un` ; do
  if [ $(ls -1 ./${MATCHING_TRIAL}/data/*core* 2>&1 | grep -v "No such file" | wc -l) -eq 0 ]; then
    if [ -r ${MATCHING_TRIAL}/SHUTDOWN_TIMEOUT_ISSUE ]; then
      sed -i "s|^MODE=4|MODE=0|" reducer${MATCHING_TRIAL}.sh
      # There is no "else" clause required here; this is a normal MODE=4 trial and not a shutdown timeout issue. It will be listed in the MODE=4 results line of pquery-results.sh, and not in the 'mysqld Shutdown Issues' line.
    fi
  else
    # There was a coredump found in this trial's directory. Thus, this issue should be handled as a non-shutdown problem. Delete the flag. This basically makes the issue a normal MODE=4 trial. Simply deleting the flag ensures that it will be listed in the MODE=4 results line of pquery-results.sh, and not in the 'mysqld Shutdown Issues' line.
    rm -f ${MATCHING_TRIAL}/SHUTDOWN_TIMEOUT_ISSUE
  fi
done

if [ ${REACH} -eq 0 ]; then # Avoid normal output if this is an automated run (REACH=1)
  echo "======================================================================================================================"
  if [ ${QC} -eq 0 ]; then
    echo -e "\nDone! Start reducer scripts like this: './reducerTRIAL.sh' or './reducer_valTRIAL.sh' where TRIAL stands for the trial number you would like to reduce. Both reducer and the SQL trace file have been pre-prepped with all the crashing queries and settings, ready for you to use without further options!"
  else
    echo -e "\nDone! Start reducer scripts like this: './qcreducerTRIAL.sh' where TRIAL stands for the trial number you would like to reduce"
  fi
  echo -e "\nIMPORTANT! Remember that settings pre-programmed into reducerTRIAL.sh by this script are in the 'Machine configurable variables' section, not in the 'User configurable variables' section. As such, and for example, if you want to change the settings (for example change MODE=3 to MODE=4), then please make such changes in the 'Machine configurable variables' section which is a bit lower in the file (search for 'Machine' to find it easily). Any changes you make in the 'User configurable variables' section will not take effect as the Machine sections overwrites these!"
  echo -e "\nIMPORTANT! Remember that a number of testcases as generated by reducer.sh will require the MYEXTRA mysqld options used in the original test. The reducer<nr>.sh scripts already have these set, but when you want to replay a testcase in some other mysqld setup, remember you will need these options passed to mysqld directly or in some my.cnf script. Note also, in reverse, that the presence of certain mysqld options that did not form part of the original test can cause the same effect; non-reproducibility of the testcase. You want a replay setup as closely matched as possible. If you use the new scripts (./{epoch}_init, _start, _stop, _cl, _run, _run-pquery, _stop etc. then these options for mysqld will already be preset for you."
fi
